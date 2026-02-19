# frozen_string_literal: true

class Agent
  # Agent::ArtifactMetrics — failure classification and artifact health accounting.
  module ArtifactMetrics
    EXTRINSIC_FAILURE_TYPES = %w[
      timeout
      provider
      network_error
      rate_limit
      rate_limited
      environment_preparing
      worker_crash
      dependency_resolution_failed
      dependency_install_failed
      dependency_activation_failed
    ].freeze
    ADAPTIVE_FAILURE_TYPES = %w[
      parse_error
      parse_failed
      low_utility
      wrong_tool_boundary
      missing_input
      invalid_format
      schema_mismatch
      contract_violation
      guardrail_retry_exhausted
      outcome_repair_retry_exhausted
    ].freeze

    private

    def _artifact_update_metrics!(artifact, state)
      _artifact_update_version_scorecard!(artifact, state)

      if state.outcome&.ok?
        _artifact_increment_success!(artifact)
      else
        _artifact_increment_failure!(artifact, state)
      end
      _artifact_update_failure_rate!(artifact)
    end

    def _artifact_increment_success!(artifact)
      artifact["success_count"] = artifact["success_count"].to_i + 1
    end

    def _artifact_increment_failure!(artifact, state)
      artifact["failure_count"] = artifact["failure_count"].to_i + 1
      failure_class = _artifact_failure_class(state)
      _artifact_increment_failure_counter!(artifact, failure_class)
      artifact["last_failure_class"] = failure_class
      artifact["last_failure_reason"] = state.outcome&.error_message || state.error&.message || "unknown failure"
    end

    def _artifact_update_failure_rate!(artifact)
      successes = artifact["success_count"].to_i
      failures = artifact["failure_count"].to_i
      total = successes + failures
      artifact["recent_failure_rate"] = total.zero? ? 0.0 : (failures.to_f / total).round(4)
    end

    def _artifact_increment_failure_counter!(artifact, failure_class)
      key = case failure_class
            when "extrinsic"
              "extrinsic_failure_count"
            when "adaptive"
              "adaptive_failure_count"
            else
              "intrinsic_failure_count"
            end
      artifact[key] = artifact[key].to_i + 1
    end

    def _artifact_failure_class(state)
      _artifact_failure_class_for(outcome: state.outcome, error: state.error)
    end

    def _artifact_failure_class_for(outcome:, error:)
      failure_type = outcome&.error_type.to_s
      return "extrinsic" if EXTRINSIC_FAILURE_TYPES.include?(failure_type)
      return "adaptive" if ADAPTIVE_FAILURE_TYPES.include?(failure_type)
      return "intrinsic" unless failure_type.empty?

      return "extrinsic" if error.is_a?(TimeoutError) || error.is_a?(ProviderError)

      "intrinsic"
    end

    def _artifact_update_version_scorecard!(artifact, state)
      checksum = artifact["code_checksum"].to_s
      return if checksum.empty?

      scorecards = artifact["scorecards"]
      scorecards = artifact["scorecards"] = {} unless scorecards.is_a?(Hash)
      scorecard = scorecards[checksum]
      scorecard = scorecards[checksum] = _artifact_scorecard_template(artifact, checksum) unless scorecard.is_a?(Hash)
      _artifact_record_scorecard_call!(scorecard, state)
    end

    def _artifact_scorecard_template(artifact, checksum)
      {
        "tool_name" => @role,
        "method_name" => artifact["method_name"].to_s,
        "artifact_checksum" => checksum,
        "calls" => 0,
        "successes" => 0,
        "failures" => 0,
        "contract_pass_count" => 0,
        "contract_fail_count" => 0,
        "guardrail_retry_exhausted_count" => 0,
        "outcome_retry_exhausted_count" => 0,
        "wrong_boundary_count" => 0,
        "provenance_violation_count" => 0,
        "state_key_observations" => [],
        "state_key_consistency_ratio" => 1.0,
        "state_key_entropy" => nil,
        "sibling_method_state_agreement" => nil,
        "sessions" => [],
        "short_window" => [],
        "medium_window" => [],
        "last_outcome_status" => nil,
        "updated_at" => nil
      }
    end

    def _artifact_record_scorecard_call!(scorecard, state)
      timestamp = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
      error_type = state.outcome&.error_type.to_s
      status = state.outcome&.ok? ? "ok" : "error"

      scorecard["calls"] = scorecard["calls"].to_i + 1
      if state.outcome&.ok?
        scorecard["successes"] = scorecard["successes"].to_i + 1
      else
        scorecard["failures"] = scorecard["failures"].to_i + 1
      end

      _artifact_update_contract_scorecard!(scorecard, state)
      scorecard["guardrail_retry_exhausted_count"] = scorecard["guardrail_retry_exhausted_count"].to_i + 1 if state.guardrail_retry_exhausted == true
      scorecard["outcome_retry_exhausted_count"] = scorecard["outcome_retry_exhausted_count"].to_i + 1 if state.outcome_repair_retry_exhausted == true
      scorecard["wrong_boundary_count"] = scorecard["wrong_boundary_count"].to_i + 1 if error_type == "wrong_tool_boundary"
      if _artifact_provenance_violation?(error_type: error_type, error_message: state.outcome&.error_message.to_s)
        scorecard["provenance_violation_count"] = scorecard["provenance_violation_count"].to_i + 1
      end

      _artifact_update_state_key_coherence!(scorecard, state)
      _artifact_append_window!(scorecard, "short_window", { "status" => status, "error_type" => error_type, "at" => timestamp }, limit: 20)
      _artifact_append_window!(scorecard, "medium_window", { "status" => status, "error_type" => error_type, "at" => timestamp }, limit: 200)
      _artifact_append_window!(scorecard, "sessions", @trace_id.to_s, limit: 200, unique: true)

      scorecard["last_outcome_status"] = status
      scorecard["updated_at"] = timestamp
    end

    def _artifact_update_contract_scorecard!(scorecard, state)
      return unless state.contract_validation_applied == true

      if state.contract_validation_passed == true
        scorecard["contract_pass_count"] = scorecard["contract_pass_count"].to_i + 1
      elsif state.contract_validation_passed == false
        scorecard["contract_fail_count"] = scorecard["contract_fail_count"].to_i + 1
      end
    end

    def _artifact_update_state_key_coherence!(scorecard, state)
      observations = Array(scorecard["state_key_observations"])
      keys = _artifact_state_keys_from_code(state.code.to_s)
      observations << keys
      observations = observations.last(200)
      scorecard["state_key_observations"] = observations

      first_keys = observations.filter_map do |entry|
        normalized = Array(entry).map(&:to_s).reject(&:empty?).sort
        normalized.first
      end
      scorecard["state_key_consistency_ratio"] =
        if first_keys.empty?
          1.0
        else
          first_keys.tally.values.max.to_f.fdiv(first_keys.length).round(4)
        end
    end

    def _artifact_state_keys_from_code(code)
      code.scan(/context\[(?::|["'])([a-zA-Z0-9_]+)["']?\]/).flatten.uniq
    end

    def _artifact_provenance_violation?(error_type:, error_message:)
      return false unless error_type == "tool_registry_violation"

      error_message.match?(/provenance/i)
    end

    def _artifact_append_window!(scorecard, key, entry, limit:, unique: false)
      values = Array(scorecard[key])
      if unique
        values << entry unless entry.to_s.empty? || values.include?(entry)
      else
        values << entry
      end
      scorecard[key] = values.last(limit)
    end
  end
end
