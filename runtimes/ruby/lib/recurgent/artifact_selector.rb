# frozen_string_literal: true

class Agent
  # Agent::ArtifactSelector — persisted artifact compatibility and selection policy.
  module ArtifactSelector
    private

    def _select_persisted_artifact(method_name, state:)
      artifact = _artifact_load(method_name)
      return nil unless artifact
      return nil unless _artifact_cacheable_for_execution?(artifact, method_name: method_name)

      selected_artifact = _artifact_selected_for_execution(artifact)
      return nil unless _artifact_compatible_for_execution?(selected_artifact)
      return nil if _artifact_degraded?(selected_artifact)

      state.artifact_prompt_version = selected_artifact["prompt_version"]
      state.artifact_contract_fingerprint = selected_artifact["contract_fingerprint"]
      state.artifact_selected_checksum = selected_artifact["code_checksum"]
      state.artifact_selected_lifecycle_state = selected_artifact["selected_lifecycle_state"]
      selected_artifact
    end

    def _artifact_cacheable_for_execution?(artifact, method_name:)
      cacheable = artifact["cacheable"]
      return cacheable == true if [true, false].include?(cacheable)

      # Legacy artifacts (pre-cacheability metadata):
      # never reuse dynamic dispatch methods, allow stable method-level tools.
      return false if _dynamic_dispatch_method?(method_name)

      true
    end

    def _artifact_compatible_for_execution?(artifact)
      return false unless _artifact_runtime_compatible?(artifact)
      return false unless _artifact_contract_compatible?(artifact)

      _artifact_checksum_valid?(artifact)
    end

    def _artifact_runtime_compatible?(artifact)
      runtime_version = artifact["runtime_version"]
      return true if runtime_version.nil?

      runtime_version.to_s == Agent::VERSION
    end

    def _artifact_contract_compatible?(artifact)
      artifact.fetch("contract_fingerprint", "none") == _artifact_contract_fingerprint
    end

    def _artifact_checksum_valid?(artifact)
      code = artifact.fetch("code", "").to_s
      return false if code.strip.empty?

      checksum = artifact["code_checksum"].to_s
      checksum == _artifact_code_checksum(code)
    end

    def _artifact_degraded?(artifact)
      lifecycle_state = artifact["selected_lifecycle_state"].to_s
      return true if lifecycle_state == "degraded"

      failures = artifact.fetch("failure_count", 0).to_i
      successes = artifact.fetch("success_count", 0).to_i
      failure_rate = artifact.fetch("recent_failure_rate", 0.0).to_f

      failures >= 3 && failure_rate > 0.6 && failures > successes
    end

    def _artifact_selected_for_execution(artifact)
      return artifact unless _promotion_enforcement_enabled?

      selected = _artifact_selected_version_checksum(artifact)
      return artifact if selected.nil?

      checksum, lifecycle_state = selected
      version_payload = artifact.fetch("versions", {})[checksum]
      return artifact unless version_payload.is_a?(Hash)

      selected_artifact = artifact.merge(
        "code" => version_payload["code"].to_s,
        "dependencies" => version_payload.fetch("dependencies", []),
        "code_checksum" => checksum,
        "selected_lifecycle_state" => lifecycle_state,
        "selected_artifact_checksum" => checksum
      )
      selected_artifact["selected_incumbent_checksum"] = artifact.dig("lifecycle", "incumbent_durable_checksum")
      selected_artifact
    end

    def _artifact_selected_version_checksum(artifact)
      lifecycle = artifact["lifecycle"]
      versions = artifact["versions"]
      return nil unless lifecycle.is_a?(Hash) && versions.is_a?(Hash)

      lifecycle_versions = lifecycle["versions"]
      return nil unless lifecycle_versions.is_a?(Hash)

      available = lifecycle_versions.each_with_object({}) do |(checksum, entry), memo|
        next unless versions.key?(checksum)
        next unless entry.is_a?(Hash)

        memo[checksum] = entry["lifecycle_state"].to_s
      end
      return nil if available.empty?

      incumbent = lifecycle["incumbent_durable_checksum"].to_s
      return [incumbent, "durable"] if !incumbent.empty? && available[incumbent] == "durable"

      durable_checksum = available.find { |_checksum, state| state == "durable" }&.first
      return [durable_checksum, "durable"] unless durable_checksum.nil?

      probation_checksum = available.find { |_checksum, state| state == "probation" }&.first
      return [probation_checksum, "probation"] unless probation_checksum.nil?

      candidate_checksum = available.find { |_checksum, state| state == "candidate" }&.first
      return [candidate_checksum, "candidate"] unless candidate_checksum.nil?

      nil
    end

    def _artifact_evaluate_promotion_shadow!(artifact, state:, timestamp:, legacy_mode: false)
      policy = _promotion_policy_contract
      state.promotion_policy_version = policy[:version]
      state.promotion_shadow_mode = _promotion_shadow_mode_enabled?
      state.promotion_enforced = _promotion_enforcement_enabled?
      return unless state.promotion_shadow_mode

      checksum = artifact["code_checksum"].to_s
      return if checksum.empty?

      lifecycle = _artifact_lifecycle_root!(
        artifact,
        policy_version: policy[:version],
        timestamp: timestamp,
        legacy_mode: legacy_mode
      )
      entry = _artifact_lifecycle_entry!(lifecycle, checksum: checksum, timestamp: timestamp)
      candidate_scorecard = _artifact_scorecard_for(artifact, artifact_checksum: checksum) || {}
      incumbent_checksum = lifecycle["incumbent_durable_checksum"].to_s
      incumbent_checksum = nil if incumbent_checksum.empty? || incumbent_checksum == checksum
      incumbent_scorecard = _artifact_scorecard_for(artifact, artifact_checksum: incumbent_checksum) if incumbent_checksum

      transition = _artifact_shadow_transition(
        entry: entry,
        state: state,
        candidate_scorecard: candidate_scorecard,
        incumbent_scorecard: incumbent_scorecard,
        policy: policy
      )
      entry["lifecycle_state"] = transition[:next_state]
      entry["last_decision"] = transition[:decision]
      entry["last_decision_at"] = timestamp
      entry["policy_version"] = policy[:version]
      lifecycle["incumbent_durable_checksum"] = checksum if transition[:next_state] == "durable"
      lifecycle["versions"][checksum] = entry
      _artifact_append_shadow_decision!(
        lifecycle,
        timestamp: timestamp,
        checksum: checksum,
        incumbent_checksum: incumbent_checksum,
        transition: transition,
        policy_version: policy[:version]
      )

      state.lifecycle_state = entry["lifecycle_state"]
      state.lifecycle_decision = transition[:decision]
      state.promotion_decision_rationale = transition[:rationale]
    end

    def _promotion_shadow_mode_enabled?
      @runtime_config.fetch(:promotion_shadow_mode_enabled, true) == true
    end

    def _promotion_enforcement_enabled?
      @runtime_config.fetch(:promotion_enforcement_enabled, false) == true
    end

    def _promotion_policy_contract
      {
        version: Agent::PROMOTION_POLICY_VERSION,
        min_calls: 10,
        min_sessions: 2,
        min_contract_pass_rate: 0.95,
        min_role_profile_pass_rate: 0.99,
        max_guardrail_retry_exhausted: 0,
        max_outcome_retry_exhausted: 0,
        max_wrong_boundary_count: 0,
        max_provenance_violations: 0,
        min_state_key_consistency_ratio: 0.5
      }
    end

    def _artifact_lifecycle_root!(artifact, policy_version:, timestamp:, legacy_mode:)
      root = artifact["lifecycle"]
      unless root.is_a?(Hash)
        root = artifact["lifecycle"] = {
          "policy_version" => policy_version,
          "incumbent_durable_checksum" => nil,
          "legacy_compatibility_mode" => legacy_mode == true,
          "versions" => {},
          "shadow_ledger" => {
            "false_promotion_count" => 0,
            "false_hold_count" => 0,
            "evaluations" => []
          },
          "created_at" => timestamp
        }
      end

      root["policy_version"] = policy_version
      root["versions"] = {} unless root["versions"].is_a?(Hash)
      root["shadow_ledger"] = {} unless root["shadow_ledger"].is_a?(Hash)
      root["shadow_ledger"]["evaluations"] = [] unless root["shadow_ledger"]["evaluations"].is_a?(Array)
      root["shadow_ledger"]["false_promotion_count"] = root["shadow_ledger"].fetch("false_promotion_count", 0).to_i
      root["shadow_ledger"]["false_hold_count"] = root["shadow_ledger"].fetch("false_hold_count", 0).to_i
      root
    end

    def _artifact_lifecycle_entry!(lifecycle, checksum:, timestamp:)
      versions = lifecycle["versions"]
      entry = versions[checksum]
      return entry if entry.is_a?(Hash)

      compatibility_mode = lifecycle["legacy_compatibility_mode"] == true
      default_state = compatibility_mode ? "probation" : "candidate"
      versions[checksum] = {
        "artifact_checksum" => checksum,
        "lifecycle_state" => default_state,
        "policy_version" => lifecycle["policy_version"],
        "incumbent_artifact_checksum" => lifecycle["incumbent_durable_checksum"],
        "compatibility_mode" => compatibility_mode,
        "first_seen_at" => timestamp,
        "last_decision" => "hold",
        "last_decision_at" => timestamp
      }
    end

    def _artifact_shadow_transition(entry:, state:, candidate_scorecard:, incumbent_scorecard:, policy:)
      current_state = entry["lifecycle_state"].to_s
      current_state = "candidate" if current_state.empty?
      metrics = _artifact_shadow_metrics(candidate_scorecard: candidate_scorecard)
      gate_pass = _artifact_probation_gate_pass?(
        metrics: metrics,
        incumbent_scorecard: incumbent_scorecard,
        policy: policy
      )
      regressed = _artifact_shadow_regressed?(metrics: metrics)
      rationale = metrics.merge(
        "observation_window_met" => metrics["calls"] >= policy[:min_calls] && metrics["session_count"] >= policy[:min_sessions],
        "gate_pass" => gate_pass,
        "profile_enabled_role" => metrics["role_profile_observation_count"] > 0
      )

      if current_state == "candidate" && state.outcome&.ok?
        return {
          decision: "continue_probation",
          next_state: "probation",
          rationale: rationale.merge("candidate_bootstrap" => true)
        }
      end

      case current_state
      when "probation"
        if _promotion_enforcement_enabled? && state.outcome&.error?
          return {
            decision: "degrade",
            next_state: "degraded",
            rationale: rationale.merge("enforced_immediate_regression" => true)
          }
        end
        return { decision: "promote", next_state: "durable", rationale: rationale } if gate_pass
        return { decision: "degrade", next_state: "degraded", rationale: rationale } if regressed

        { decision: "continue_probation", next_state: "probation", rationale: rationale }
      when "durable"
        return { decision: "degrade", next_state: "degraded", rationale: rationale } if regressed

        { decision: "hold", next_state: "durable", rationale: rationale }
      when "degraded"
        return { decision: "promote", next_state: "durable", rationale: rationale } if gate_pass

        { decision: "hold", next_state: "degraded", rationale: rationale }
      else
        { decision: "hold", next_state: "candidate", rationale: rationale }
      end
    end

    def _artifact_shadow_metrics(candidate_scorecard:)
      calls = candidate_scorecard.fetch("calls", 0).to_i
      successes = candidate_scorecard.fetch("successes", 0).to_i
      failures = candidate_scorecard.fetch("failures", 0).to_i
      contract_pass_count = candidate_scorecard.fetch("contract_pass_count", 0).to_i
      contract_fail_count = candidate_scorecard.fetch("contract_fail_count", 0).to_i
      contract_total = contract_pass_count + contract_fail_count
      contract_pass_rate = contract_total.zero? ? 1.0 : contract_pass_count.to_f.fdiv(contract_total)
      session_count = Array(candidate_scorecard["sessions"]).uniq.length
      {
        "calls" => calls,
        "successes" => successes,
        "failures" => failures,
        "failure_rate" => (calls.zero? ? 0.0 : failures.to_f.fdiv(calls)).round(4),
        "session_count" => session_count,
        "contract_pass_rate" => contract_pass_rate.round(4),
        "guardrail_retry_exhausted" => candidate_scorecard.fetch("guardrail_retry_exhausted_count", 0).to_i,
        "outcome_retry_exhausted" => candidate_scorecard.fetch("outcome_retry_exhausted_count", 0).to_i,
        "wrong_boundary_count" => candidate_scorecard.fetch("wrong_boundary_count", 0).to_i,
        "provenance_violations" => candidate_scorecard.fetch("provenance_violation_count", 0).to_i,
        "state_key_consistency_ratio" => candidate_scorecard.fetch("state_key_consistency_ratio", 1.0).to_f.round(4),
        "role_profile_observation_count" => candidate_scorecard.fetch("role_profile_observation_count", 0).to_i,
        "role_profile_pass_rate" => candidate_scorecard.fetch("role_profile_pass_rate", 1.0).to_f.round(4)
      }
    end

    def _artifact_probation_gate_pass?(metrics:, incumbent_scorecard:, policy:)
      return false if metrics["calls"] < policy[:min_calls]
      return false if metrics["session_count"] < policy[:min_sessions]
      return false if metrics["contract_pass_rate"] < policy[:min_contract_pass_rate]
      return false if metrics["guardrail_retry_exhausted"] > policy[:max_guardrail_retry_exhausted]
      return false if metrics["outcome_retry_exhausted"] > policy[:max_outcome_retry_exhausted]
      return false if metrics["wrong_boundary_count"] > policy[:max_wrong_boundary_count]
      return false if metrics["provenance_violations"] > policy[:max_provenance_violations]
      return false if metrics["state_key_consistency_ratio"] < policy[:min_state_key_consistency_ratio]
      if metrics["role_profile_observation_count"] > 0
        min_profile_pass_rate = policy[:min_role_profile_pass_rate] || 0.99
        return false if metrics["role_profile_pass_rate"] < min_profile_pass_rate
      end

      incumbent_contract_rate = _artifact_incumbent_contract_pass_rate(incumbent_scorecard)
      metrics["contract_pass_rate"] >= incumbent_contract_rate
    end

    def _artifact_incumbent_contract_pass_rate(incumbent_scorecard)
      return 0.0 unless incumbent_scorecard.is_a?(Hash)

      pass_count = incumbent_scorecard.fetch("contract_pass_count", 0).to_i
      fail_count = incumbent_scorecard.fetch("contract_fail_count", 0).to_i
      total = pass_count + fail_count
      return 0.0 if total.zero?

      pass_count.to_f.fdiv(total).round(4)
    end

    def _artifact_shadow_regressed?(metrics:)
      metrics["calls"] >= 3 && metrics["failure_rate"] > 0.6 && metrics["failures"] > metrics["successes"]
    end

    def _artifact_append_shadow_decision!(lifecycle, timestamp:, checksum:, incumbent_checksum:, transition:, policy_version:)
      ledger = lifecycle["shadow_ledger"]
      evaluations = Array(ledger["evaluations"])
      evaluations << {
        "decision_type" => "promotion_evaluation",
        "tool_name" => @role,
        "candidate_artifact_id" => checksum,
        "incumbent_artifact_id" => incumbent_checksum,
        "decision" => transition[:decision],
        "policy_version" => policy_version,
        "window" => "rolling_medium_window",
        "rationale" => transition[:rationale],
        "at" => timestamp
      }
      ledger["evaluations"] = evaluations.last(200)
    end
  end
end
