# frozen_string_literal: true

class Agent
  # Agent::FreshOutcomeRepair — fresh-call retry handling for retriable Outcome.error results.
  module FreshOutcomeRepair
    private

    def _handle_outcome_retry_or_return(
      method_name:,
      state:,
      attempt_snapshot:,
      outcome:,
      guardrail_recovery_attempts:,
      execution_repair_attempts:,
      outcome_repair_attempts:
    )
      if outcome.ok? || !outcome.retriable
        return _outcome_passthrough_result(
          outcome,
          guardrail_recovery_attempts,
          execution_repair_attempts,
          outcome_repair_attempts
        )
      end

      failure_class = _artifact_failure_class_for(outcome: outcome, error: nil)
      state.failure_class = failure_class
      if failure_class == "extrinsic"
        return _outcome_passthrough_result(
          outcome,
          guardrail_recovery_attempts,
          execution_repair_attempts,
          outcome_repair_attempts
        )
      end

      _restore_attempt_snapshot!(attempt_snapshot)
      state.rollback_applied = true
      state.attempt_stage = "outcome_retry"
      state.validation_failure_type = outcome.error_type.to_s
      state.outcome_repair_triggered = true

      if outcome_repair_attempts >= @fresh_outcome_repair_budget
        _raise_outcome_repair_exhausted!(
          method_name: method_name,
          state: state,
          outcome: outcome,
          attempts: outcome_repair_attempts
        )
      end

      next_attempts = outcome_repair_attempts + 1
      state.outcome_repair_attempts = next_attempts
      next_feedback = _classify_outcome_failure(outcome).merge(
        attempt_number: state.attempt_id + 1,
        remaining_budget: @fresh_outcome_repair_budget - next_attempts
      )
      [nil, nil, nil, next_feedback, guardrail_recovery_attempts, execution_repair_attempts, next_attempts]
    end

    def _outcome_passthrough_result(outcome, guardrail_attempts, execution_attempts, outcome_attempts)
      [outcome, nil, nil, nil, guardrail_attempts, execution_attempts, outcome_attempts]
    end

    def _raise_outcome_repair_exhausted!(method_name:, state:, outcome:, attempts:)
      state.outcome_repair_retry_exhausted = true
      raise OutcomeRepairRetryExhaustedError.new(
        "Retriable outcome-error repairs exhausted for #{@role}.#{method_name}",
        metadata: {
          outcome_repair_attempts: attempts,
          last_error_type: outcome.error_type,
          last_error_message: outcome.error_message
        }
      )
    end
  end
end
