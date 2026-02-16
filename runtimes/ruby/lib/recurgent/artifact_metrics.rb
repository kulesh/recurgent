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
  end
end
