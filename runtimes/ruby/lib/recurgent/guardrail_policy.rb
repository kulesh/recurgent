# frozen_string_literal: true

class Agent
  # Agent::GuardrailPolicy — guardrail retry prompting, violation classification,
  # generated-code pattern checks, outcome-error feedback, and boundary normalization.
  module GuardrailPolicy
    # -- Constants ---------------------------------------------------------------

    EXTERNAL_RETRIEVAL_MODES = %w[live cached fixture].freeze
    NORMALIZATION_POLICY = "guardrail_exhaustion_boundary_v1"
    USER_MESSAGE = "This request couldn't be completed after multiple attempts."

    private

    # -- Retry prompt assembly ---------------------------------------------------

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

    # -- Budget validation -------------------------------------------------------

    def _validate_guardrail_recovery_budget(value)
      return value if value.is_a?(Integer) && value >= 0

      raise ArgumentError, "guardrail_recovery_budget must be an Integer >= 0"
    end

    def _validate_fresh_outcome_repair_budget(value)
      return value if value.is_a?(Integer) && value >= 0

      raise ArgumentError, "fresh_outcome_repair_budget must be an Integer >= 0"
    end

    # -- Violation classification ------------------------------------------------

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

    # -- Execution failure classification ----------------------------------------

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

    # -- Guardrail failure state -------------------------------------------------

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

    # -- Generated-code pattern checks -------------------------------------------

    def _context_tools_shape_misuse?(source)
      match = source.match(/context\[:tools\].*?\{\s*\|([a-zA-Z_]\w*)\|/m)
      return false unless match

      item_var = match[1]
      source.match?(/\b#{Regexp.escape(item_var)}\s*\[\s*(?::name|["']name["'])\s*\]/)
    end

    def _hardcoded_external_fallback_success?(source)
      normalized_source = _source_without_ruby_comments(source)
      fetch_like = normalized_source.match?(%r{Net::HTTP|net/http|tool\(["']web_fetcher["']\)|fetch_result}i)
      return false unless fetch_like

      fallback_var = normalized_source.match(/\b(fallback_[a-zA-Z_]\w*)\s*=\s*\[/)&.captures&.first
      return false if fallback_var.nil?

      normalized_source.match?(/\bOutcome\.ok\(\s*#{Regexp.escape(fallback_var)}\s*\)/)
    end

    def _missing_external_provenance_success?(source, outcome)
      return false unless outcome.is_a?(Outcome) && outcome.ok?
      return false unless _external_data_flow_source?(source)

      !_outcome_value_has_external_provenance?(outcome.value)
    end

    def _validate_generated_code_policy!(_method_name, code)
      source = code.to_s
      if source.match?(/\.\s*define_singleton_method\s*\(/)
        raise ToolRegistryViolationError,
              "Defining singleton methods on Agent instances is not supported; use tool/delegate invocation paths."
      end

      if _context_tools_shape_misuse?(source)
        raise ToolRegistryViolationError,
              "context[:tools] is a Hash keyed by tool name; use key? or iterate |tool_name, metadata| " \
              "(not |t| with t[:name])."
      end

      return unless _hardcoded_external_fallback_success?(source)

      raise ToolRegistryViolationError,
            "Hardcoded fallback payloads for external-fetch flows must not return Outcome.ok; " \
            "emit low_utility/unsupported_capability instead."
    end

    def _validate_generated_outcome_policy!(_method_name, code, outcome)
      source = code.to_s
      return unless _missing_external_provenance_success?(source, outcome)

      raise ToolRegistryViolationError,
            "External-data success must include `provenance.sources[]` with " \
            "`uri`, `fetched_at`, `retrieval_tool`, and `retrieval_mode` (`live|cached|fixture`)."
    end

    def _external_data_flow_source?(source)
      normalized_source = _source_without_ruby_comments(source)
      normalized_source.match?(%r{
        tool\(\s*["'][\w-]*fetch[\w-]*["']\s*\)|
        delegate\(\s*["'][\w-]*fetch[\w-]*["']\s*[,)]|
        require\s*["']net/http["']|
        \bNet::HTTP\b
      }ix)
    end

    def _outcome_value_has_external_provenance?(value)
      return false unless value.is_a?(Hash)

      provenance = _guardrail_hash_value(value, :provenance)
      return false unless provenance.is_a?(Hash)

      sources = _guardrail_hash_value(provenance, :sources)
      return false unless sources.is_a?(Array) && !sources.empty?

      sources.all? { |source_entry| _valid_provenance_source_entry?(source_entry) }
    end

    def _valid_provenance_source_entry?(source_entry)
      return false unless source_entry.is_a?(Hash)
      return false unless _provenance_source_required_fields_present?(source_entry)

      EXTERNAL_RETRIEVAL_MODES.include?(_provenance_source_retrieval_mode(source_entry))
    end

    def _provenance_source_required_fields_present?(source_entry)
      required_fields = %i[uri fetched_at retrieval_tool]
      required_fields.all? do |field|
        !_guardrail_blank?(_guardrail_hash_value(source_entry, field))
      end
    end

    def _provenance_source_retrieval_mode(source_entry)
      mode = _guardrail_hash_value(source_entry, :retrieval_mode)
      return nil if mode.nil?

      mode.to_s.strip.downcase
    end

    def _guardrail_hash_value(hash_value, key)
      hash_value[key] || hash_value[key.to_s]
    end

    def _guardrail_blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def _source_without_ruby_comments(source)
      source.each_line.map { |line| line.sub(/#.*$/, "") }.join("\n")
    end

    # -- Outcome-error retry feedback --------------------------------------------

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

    # -- Boundary normalization --------------------------------------------------

    def _normalize_top_level_guardrail_exhaustion_payload(payload:, error:, call_context:)
      return payload unless payload[:error_type] == "guardrail_retry_exhausted"
      return payload unless _top_level_call_context?(call_context)

      metadata = payload[:metadata].is_a?(Hash) ? payload[:metadata].dup : {}
      metadata[:normalized] = true
      metadata[:normalization_policy] = NORMALIZATION_POLICY
      metadata[:guardrail_class] ||= "recoverable_guardrail"
      metadata[:guardrail_subtype] = metadata[:last_violation_subtype] || "unknown_guardrail_violation"
      metadata[:raw_error_message] ||= error.message.to_s

      payload.merge(
        error_message: USER_MESSAGE,
        metadata: metadata
      )
    end

    def _top_level_call_context?(call_context)
      return false unless call_context.is_a?(Hash)

      call_context.fetch(:depth, nil).to_i.zero?
    end
  end
end
