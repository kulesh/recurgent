# frozen_string_literal: true

class Agent
  # Agent::ObservabilityAttemptFields — attempt-lifecycle observability field mapping.
  module ObservabilityAttemptFields
    private

    def _core_attempt_fields(log_context)
      {
        attempt_id: log_context[:attempt_id],
        attempt_stage: log_context[:attempt_stage],
        validation_failure_type: log_context[:validation_failure_type],
        rollback_applied: log_context[:rollback_applied],
        retry_feedback_injected: log_context[:retry_feedback_injected],
        attempt_failures: log_context[:attempt_failures],
        latest_failure_stage: log_context[:latest_failure_stage],
        latest_failure_class: log_context[:latest_failure_class],
        latest_failure_message: log_context[:latest_failure_message],
        execution_receiver: log_context[:execution_receiver],
        guardrail_violation_subtype: log_context[:guardrail_violation_subtype],
        guardrail_recovery_attempts: log_context[:guardrail_recovery_attempts],
        execution_repair_attempts: log_context[:execution_repair_attempts],
        outcome_repair_attempts: log_context[:outcome_repair_attempts],
        outcome_repair_triggered: log_context[:outcome_repair_triggered],
        guardrail_retry_exhausted: log_context[:guardrail_retry_exhausted],
        outcome_repair_retry_exhausted: log_context[:outcome_repair_retry_exhausted],
        solver_shape: log_context[:solver_shape],
        solver_shape_complete: log_context[:solver_shape_complete],
        solver_shape_stance: _solver_shape_log_value(log_context, :stance),
        solver_shape_promotion_intent: _solver_shape_log_value(log_context, :promotion_intent),
        self_model: log_context[:self_model],
        awareness_level: log_context[:awareness_level],
        authority: log_context[:authority],
        active_contract_version: log_context[:active_contract_version],
        active_role_profile_version: log_context[:active_role_profile_version],
        execution_snapshot_ref: log_context[:execution_snapshot_ref],
        evolution_snapshot_ref: log_context[:evolution_snapshot_ref],
        namespace_key_collision_count: log_context[:namespace_key_collision_count],
        namespace_multi_lifetime_key_count: log_context[:namespace_multi_lifetime_key_count],
        namespace_continuity_violation_count: log_context[:namespace_continuity_violation_count],
        promotion_policy_version: log_context[:promotion_policy_version],
        lifecycle_state: log_context[:lifecycle_state],
        lifecycle_decision: log_context[:lifecycle_decision],
        promotion_decision_rationale: log_context[:promotion_decision_rationale],
        promotion_shadow_mode: log_context[:promotion_shadow_mode],
        promotion_enforced: log_context[:promotion_enforced]
      }
    end

    def _solver_shape_log_value(log_context, key)
      solver_shape = log_context[:solver_shape]
      return nil unless solver_shape.is_a?(Hash)

      solver_shape[key] || solver_shape[key.to_s]
    end
  end
end
