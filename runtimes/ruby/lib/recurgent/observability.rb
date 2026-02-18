# frozen_string_literal: true

class Agent
  # Agent::Observability — log entry building, JSON safety, UTF-8 normalization, trace linkage.
  # Reads: @role, @model_name, @delegation_contract, @delegation_contract_source, @context, @debug
  module Observability
    private

    # -- JSON / UTF-8 normalization (formerly Agent::JsonNormalization) --------

    def _json_safe(value)
      case value
      when String
        _normalize_utf8(value)
      when Array
        value.map { |item| _json_safe(item) }
      when Hash
        value.each_with_object({}) do |(key, item), normalized|
          normalized[_json_safe_hash_key(key)] = _json_safe(item)
        end
      else
        value
      end
    end

    def _normalize_utf8(value)
      normalized = value.dup
      normalized.force_encoding(Encoding::UTF_8)
      return normalized if normalized.valid_encoding?

      normalized.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
    end

    def _json_safe_hash_key(key)
      return _normalize_utf8(key) if key.is_a?(String)
      return key if key.is_a?(Symbol)

      key
    end

    # -- Conversation-history observability fields (formerly Agent::ObservabilityHistoryFields) --

    def _core_history_fields(log_context)
      {
        history_record_appended: log_context[:history_record_appended],
        conversation_history_size: log_context[:conversation_history_size],
        history_access_detected: log_context[:history_access_detected],
        history_query_patterns: log_context[:history_query_patterns]
      }
    end

    # -- Attempt-lifecycle observability fields (formerly Agent::ObservabilityAttemptFields) --

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
        outcome_repair_retry_exhausted: log_context[:outcome_repair_retry_exhausted]
      }
    end

    # -- Log entry building ----------------------------------------------------

    def _build_log_entry(log_context)
      entry = _base_log_entry(log_context)
      _add_contract_to_entry(entry)
      _add_outcome_to_entry(entry, log_context[:outcome]) if log_context[:outcome]
      _add_error_to_entry(entry, log_context[:error]) if log_context[:error]
      _add_debug_section(entry, log_context) if @debug
      entry
    end

    def _base_log_entry(log_context)
      _core_log_fields(log_context)
        .merge(_contract_validation_log_fields(log_context))
        .merge(_artifact_cache_log_fields(log_context))
        .merge(_trace_log_fields(log_context))
        .merge(_environment_log_fields(log_context))
    end

    def _core_log_fields(log_context)
      _core_identity_fields(log_context)
        .merge(_core_program_fields(log_context))
        .merge(_core_pattern_fields(log_context))
        .merge(_core_history_fields(log_context))
        .merge(_core_attempt_fields(log_context))
    end

    def _core_identity_fields(log_context)
      {
        timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
        runtime: Agent::RUNTIME_NAME,
        role: @role,
        model: @model_name,
        method: log_context[:method_name],
        args: log_context[:args],
        kwargs: log_context[:kwargs],
        contract_source: @delegation_contract_source,
        duration_ms: log_context[:duration_ms].round(1),
        generation_attempt: log_context[:generation_attempt]
      }
    end

    def _core_program_fields(log_context)
      {
        code: log_context[:code],
        program_dependencies: log_context[:program_dependencies],
        normalized_dependencies: log_context[:normalized_dependencies],
        program_source: log_context[:program_source],
        repair_attempted: log_context[:repair_attempted],
        repair_succeeded: log_context[:repair_succeeded],
        failure_class: log_context[:failure_class]
      }
    end

    def _core_pattern_fields(log_context)
      {
        capability_patterns: log_context[:capability_patterns],
        user_correction_detected: log_context[:user_correction_detected],
        user_correction_signal: log_context[:user_correction_signal],
        user_correction_reference_call_id: log_context[:user_correction_reference_call_id]
      }
    end

    def _contract_validation_log_fields(log_context)
      {
        contract_validation_applied: log_context[:contract_validation_applied],
        contract_validation_passed: log_context[:contract_validation_passed],
        contract_validation_mismatch: log_context[:contract_validation_mismatch],
        contract_validation_expected_keys: log_context[:contract_validation_expected_keys],
        contract_validation_actual_keys: log_context[:contract_validation_actual_keys]
      }
    end

    def _artifact_cache_log_fields(log_context)
      {
        artifact_hit: log_context[:artifact_hit],
        artifact_prompt_version: log_context[:artifact_prompt_version],
        artifact_contract_fingerprint: log_context[:artifact_contract_fingerprint],
        cacheable: log_context[:cacheable],
        cacheability_reason: log_context[:cacheability_reason],
        input_sensitive: log_context[:input_sensitive]
      }
    end

    def _trace_log_fields(log_context)
      {
        trace_id: log_context[:call_context]&.fetch(:trace_id, nil),
        call_id: log_context[:call_context]&.fetch(:call_id, nil),
        parent_call_id: log_context[:call_context]&.fetch(:parent_call_id, nil),
        depth: log_context[:call_context]&.fetch(:depth, nil)
      }
    end

    def _environment_log_fields(log_context)
      {
        env_id: log_context[:env_id],
        environment_cache_hit: log_context[:environment_cache_hit],
        env_prepare_ms: log_context[:env_prepare_ms],
        env_resolve_ms: log_context[:env_resolve_ms],
        env_install_ms: log_context[:env_install_ms],
        worker_pid: log_context[:worker_pid],
        worker_restart_count: log_context[:worker_restart_count],
        prep_ticket_id: log_context[:prep_ticket_id]
      }
    end

    def _add_debug_section(entry, log_context)
      _add_debug_to_entry(
        entry,
        log_context[:system_prompt],
        log_context[:user_prompt],
        log_context[:error],
        log_context[:capability_pattern_evidence]
      )
    end

    def _add_error_to_entry(entry, error)
      entry[:error_class] = error.class.name
      entry[:error_message] = error.message
    end

    def _add_contract_to_entry(entry)
      return unless @delegation_contract

      entry[:contract_purpose] = @delegation_contract[:purpose]
      entry[:contract_deliverable] = @delegation_contract[:deliverable]
      entry[:contract_acceptance] = @delegation_contract[:acceptance]
      entry[:contract_failure_policy] = @delegation_contract[:failure_policy]
    end

    def _add_outcome_to_entry(entry, outcome)
      entry.merge!(_outcome_base_fields(outcome))
      return _add_ok_outcome_to_entry(entry, outcome) if outcome.ok?

      _add_error_outcome_to_entry(entry, outcome)
    end

    def _outcome_base_fields(outcome)
      {
        outcome_status: outcome.status,
        outcome_retriable: outcome.retriable,
        outcome_tool_role: outcome.tool_role,
        outcome_method_name: outcome.method_name
      }
    end

    def _add_ok_outcome_to_entry(entry, outcome)
      entry[:outcome_value_class] = outcome.value.class.name unless outcome.value.nil?
      entry[:outcome_value] = _debug_serializable_value(outcome.value) if @debug
    end

    def _add_error_outcome_to_entry(entry, outcome)
      entry[:outcome_error_type] = outcome.error_type
      entry[:outcome_error_message] = outcome.error_message
      entry[:outcome_error_metadata] = outcome.metadata unless outcome.metadata.nil? || outcome.metadata.empty?
    end

    def _add_debug_to_entry(entry, system_prompt, user_prompt, error, capability_pattern_evidence)
      entry[:system_prompt] = system_prompt
      entry[:user_prompt] = user_prompt
      entry[:context] = @context.dup
      entry[:capability_pattern_evidence] = capability_pattern_evidence
      entry[:error_backtrace] = error.backtrace&.first(10) if error
    end

    # Keep debug logs robust when runtime values are not JSON-friendly.
    def _debug_serializable_value(value)
      JSON.parse(JSON.generate(_json_safe(value)))
    rescue JSON::GeneratorError, TypeError
      value.inspect
    end
  end
end
