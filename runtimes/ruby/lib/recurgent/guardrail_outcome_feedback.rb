# frozen_string_literal: true

class Agent
  # Agent::GuardrailOutcomeFeedback — outcome-error retry prompting and correction classification.
  module GuardrailOutcomeFeedback
    private

    def _outcome_retry_user_prompt(base_user_prompt, feedback)
      return base_user_prompt if feedback.nil?

      <<~PROMPT
        #{base_user_prompt}

        <outcome_failure_feedback>
        <failure_type>#{feedback[:failure_type]}</failure_type>
        <failure_message>#{feedback[:failure_message]}</failure_message>
        <root_error_class>#{feedback[:root_error_class]}</root_error_class>
        <root_error_message>#{feedback[:root_error_message]}</root_error_message>
        <required_correction>#{feedback[:required_correction]}</required_correction>
        <attempt_number>#{feedback[:attempt_number]}</attempt_number>
        <remaining_outcome_repair_budget>#{feedback[:remaining_budget]}</remaining_outcome_repair_budget>
        </outcome_failure_feedback>

        IMPORTANT: Previous attempt returned a retriable error outcome.
        Regenerate code that preserves intended behavior and avoids this outcome failure path.
      PROMPT
    end

    def _classify_outcome_failure(outcome)
      message = outcome.error_message.to_s
      failure_type = outcome.error_type.to_s
      failure_type = "execution" if failure_type.empty?
      {
        failure_type: failure_type,
        failure_message: message,
        root_error_class: _outcome_root_error_class(message),
        root_error_message: message,
        required_correction: _outcome_required_correction(message)
      }
    end

    def _outcome_required_correction(message)
      if message.match?(/undefined method [`'"][^`'"]+[`'"] for an instance of Agent::Outcome/i)
        return "Unwrap Outcome values before parsing: branch with `outcome.ok?` and operate on `outcome.value`, not on Outcome itself."
      end

      _execution_required_correction(message)
    end

    def _outcome_root_error_class(message)
      return "NoMethodError" if message.match?(/NoMethodError/i)
      return "TypeError" if message.match?(/TypeError/i)

      "OutcomeError"
    end
  end
end
