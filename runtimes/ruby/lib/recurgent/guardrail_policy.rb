# frozen_string_literal: true

class Agent
  # Agent::GuardrailPolicy — guardrail retry prompting and violation classification.
  module GuardrailPolicy
    include GuardrailOutcomeFeedback
    include GuardrailCodeChecks

    private

    def _fresh_retry_user_prompt(base_user_prompt, guardrail_feedback:, execution_feedback:, outcome_feedback:)
      with_guardrail_feedback = _guardrail_retry_user_prompt(base_user_prompt, guardrail_feedback)
      with_execution_feedback = _execution_retry_user_prompt(with_guardrail_feedback, execution_feedback)
      _outcome_retry_user_prompt(with_execution_feedback, outcome_feedback)
    end

    def _guardrail_retry_user_prompt(base_user_prompt, feedback)
      return base_user_prompt if feedback.nil?

      <<~PROMPT
        #{base_user_prompt}

        <guardrail_feedback>
        <guardrail_class>#{feedback[:guardrail_class]}</guardrail_class>
        <violation_type>#{feedback[:violation_type]}</violation_type>
        <violation_subtype>#{feedback[:violation_subtype]}</violation_subtype>
        <violation_message>#{feedback[:violation_message]}</violation_message>
        <violation_location>#{feedback[:violation_location] || "unknown"}</violation_location>
        <required_correction>#{feedback[:required_correction]}</required_correction>
        <attempt_number>#{feedback[:attempt_number]}</attempt_number>
        <remaining_guardrail_budget>#{feedback[:remaining_budget]}</remaining_guardrail_budget>
        </guardrail_feedback>

        IMPORTANT: Previous attempt violated runtime guardrails.
        Regenerate code that satisfies the required correction exactly.
        Do not repeat the prohibited mechanism.
      PROMPT
    end

    def _execution_retry_user_prompt(base_user_prompt, feedback)
      return base_user_prompt if feedback.nil?

      <<~PROMPT
        #{base_user_prompt}

        <execution_failure_feedback>
        <failure_type>#{feedback[:failure_type]}</failure_type>
        <failure_message>#{feedback[:failure_message]}</failure_message>
        <root_error_class>#{feedback[:root_error_class]}</root_error_class>
        <root_error_message>#{feedback[:root_error_message]}</root_error_message>
        <failure_location>#{feedback[:failure_location] || "unknown"}</failure_location>
        <required_correction>#{feedback[:required_correction]}</required_correction>
        <attempt_number>#{feedback[:attempt_number]}</attempt_number>
        <remaining_execution_repair_budget>#{feedback[:remaining_budget]}</remaining_execution_repair_budget>
        </execution_failure_feedback>

        IMPORTANT: Previous attempt failed during execution.
        Regenerate code that avoids this runtime failure while preserving intended behavior.
      PROMPT
    end

    def _validate_guardrail_recovery_budget(value)
      return value if value.is_a?(Integer) && value >= 0

      raise ArgumentError, "guardrail_recovery_budget must be an Integer >= 0"
    end

    def _validate_fresh_outcome_repair_budget(value)
      return value if value.is_a?(Integer) && value >= 0

      raise ArgumentError, "fresh_outcome_repair_budget must be an Integer >= 0"
    end

    def _error_type_for_exception(error)
      ERROR_TYPE_BY_CLASS.find { |klass, _| error.is_a?(klass) }&.last || "execution"
    end

    def _classify_guardrail_violation(error)
      violation_message = error.message.to_s
      guardrail_class = if TERMINAL_GUARDRAIL_MESSAGE_PATTERNS.any? { |pattern| violation_message.match?(pattern) }
                          "terminal_guardrail"
                        else
                          "recoverable_guardrail"
                        end
      {
        guardrail_class: guardrail_class,
        violation_type: _error_type_for_exception(error),
        violation_subtype: _guardrail_violation_subtype(violation_message),
        violation_message: violation_message,
        violation_location: _guardrail_violation_location(error),
        required_correction: _guardrail_required_correction(violation_message)
      }
    end

    def _guardrail_violation_location(error)
      trace_line = error.backtrace&.first.to_s
      return nil if trace_line.empty?

      trace_line
    end

    def _guardrail_required_correction(message)
      if message.match?(/singleton methods on Agent instances/i)
        return "Materialize tools with tool(\"name\") or delegate(\"name\", ...), then call dynamic methods; " \
               "do not define singleton methods."
      end
      if message.match?(/context\[:tools\] is a Hash keyed by tool name/i)
        return "Use `context[:tools].key?(\"tool_name\")` for existence checks, or iterate " \
               "`context[:tools].each do |tool_name, metadata| ... end`."
      end
      if message.match?(/Hardcoded fallback payloads for external-fetch flows/i)
        return "Do not return hardcoded fallback lists as `Outcome.ok`. Return typed `low_utility` (or " \
               "`unsupported_capability`) unless output is derived from actual fetched/parsing results."
      end
      if message.match?(/External-data success must include `provenance\.sources\[\]`/i)
        return "For external-data success, return a value with `provenance: { sources: [...] }` and include " \
               "`uri`, `fetched_at`, `retrieval_tool`, `retrieval_mode` (`live|cached|fixture`) for each source."
      end

      "Rewrite using policy-compliant tool/delegate invocation paths and avoid executable metadata mutation."
    end

    def _guardrail_violation_subtype(message)
      return "singleton_method_mutation" if message.match?(/singleton methods on Agent instances/i)
      return "context_tools_shape_misuse" if message.match?(/context\[:tools\] is a Hash keyed by tool name/i)
      return "hardcoded_external_fallback_success" if message.match?(/Hardcoded fallback payloads for external-fetch flows/i)
      return "missing_external_provenance" if message.match?(/External-data success must include `provenance\.sources\[\]`/i)

      "unknown_guardrail_violation"
    end

    def _classify_execution_failure(error)
      root_error = error.cause || error
      root_message = root_error.message.to_s
      {
        failure_type: _error_type_for_exception(error),
        failure_message: error.message.to_s,
        root_error_class: root_error.class.name,
        root_error_message: root_message,
        failure_location: _guardrail_violation_location(root_error),
        required_correction: _execution_required_correction(root_message)
      }
    end

    def _execution_required_correction(message)
      if message.match?(/undefined method [`'"]success\?[`'"]/i)
        return "Use Outcome API `ok?` / `error?` for branching; `success?` is tolerated alias but prefer `ok?`."
      end
      if message.match?(/undefined method [`'"]<<[`'"] for nil/i)
        return "Initialize accumulators before append operations (for example `response = +\"\"` or `lines = []`)."
      end

      "Fix the runtime exception path and regenerate code with explicit nil/shape checks before method calls."
    end

    def _apply_guardrail_failure_state!(state, error)
      state.rollback_applied = true
      state.attempt_stage = "rolled_back"
      state.validation_failure_type = _error_type_for_exception(error)
    end

    def _next_guardrail_retry_feedback!(method_name:, state:, classification:, guardrail_recovery_attempts:)
      next_attempts = guardrail_recovery_attempts + 1
      state.guardrail_recovery_attempts = next_attempts
      remaining_budget = @guardrail_recovery_budget - next_attempts
      if remaining_budget.negative?
        state.guardrail_retry_exhausted = true
        raise GuardrailRetryExhaustedError.new(
          "Recoverable guardrail retries exhausted for #{@role}.#{method_name}",
          metadata: {
            guardrail_recovery_attempts: next_attempts,
            last_violation_type: classification[:violation_type],
            last_violation_subtype: classification[:violation_subtype],
            last_violation_message: classification[:violation_message]
          }
        )
      end

      [
        classification.merge(
          attempt_number: state.attempt_id + 1,
          remaining_budget: remaining_budget
        ),
        next_attempts
      ]
    end
  end
end
