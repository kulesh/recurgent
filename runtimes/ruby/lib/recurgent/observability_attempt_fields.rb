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
        guardrail_recovery_attempts: log_context[:guardrail_recovery_attempts],
        execution_repair_attempts: log_context[:execution_repair_attempts],
        guardrail_retry_exhausted: log_context[:guardrail_retry_exhausted]
      }
    end
  end
end
