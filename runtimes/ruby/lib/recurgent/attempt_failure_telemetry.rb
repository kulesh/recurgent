# frozen_string_literal: true

class Agent
  # Agent::AttemptFailureTelemetry — tracks failed attempt diagnostics across recovery lanes.
  module AttemptFailureTelemetry
    ATTEMPT_FAILURE_STAGES = %w[validation execution outcome_policy].freeze
    MAX_ATTEMPT_FAILURES_RECORDED = 8
    MAX_FAILURE_MESSAGE_LENGTH = 400

    private

    def _record_attempt_failure_from_error!(state:, stage:, error:)
      _record_attempt_failure!(
        state: state,
        stage: stage,
        error_class: error.class.name,
        error_message: error.message.to_s
      )
    end

    def _record_attempt_failure_from_outcome!(state:, stage:, outcome:)
      _record_attempt_failure!(
        state: state,
        stage: stage,
        error_class: "Agent::OutcomeError",
        error_message: "#{outcome.error_type}: #{outcome.error_message}"
      )
    end

    def _record_attempt_failure!(state:, stage:, error_class:, error_message:)
      normalized_stage = _normalize_attempt_failure_stage(stage)
      call_id = _call_stack.last&.fetch(:call_id, nil)
      entry = {
        attempt_id: state.attempt_id,
        stage: normalized_stage,
        error_class: error_class.to_s,
        error_message: _truncate_failure_message(error_message),
        timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
        call_id: call_id
      }
      failures = Array(state.attempt_failures)
      failures << entry
      state.attempt_failures = failures.last(MAX_ATTEMPT_FAILURES_RECORDED)
      state.latest_failure_stage = normalized_stage
      state.latest_failure_class = entry[:error_class]
      state.latest_failure_message = entry[:error_message]
    end

    def _normalize_attempt_failure_stage(stage)
      candidate = stage.to_s
      ATTEMPT_FAILURE_STAGES.include?(candidate) ? candidate : "execution"
    end

    def _truncate_failure_message(message)
      normalized = _normalize_utf8(message.to_s)
      return normalized if normalized.length <= MAX_FAILURE_MESSAGE_LENGTH

      "#{normalized[0, MAX_FAILURE_MESSAGE_LENGTH - 3]}..."
    end
  end
end
