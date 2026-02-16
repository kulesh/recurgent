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
        execution_receiver: log_context[:execution_receiver],
        guardrail_recovery_attempts: log_context[:guardrail_recovery_attempts],
        execution_repair_attempts: log_context[:execution_repair_attempts],
        outcome_repair_attempts: log_context[:outcome_repair_attempts],
        outcome_repair_triggered: log_context[:outcome_repair_triggered],
        guardrail_retry_exhausted: log_context[:guardrail_retry_exhausted],
        outcome_repair_retry_exhausted: log_context[:outcome_repair_retry_exhausted]
      }
    end
  end
end
