# frozen_string_literal: true

class Agent
  # Agent::Observability — log entry building, JSON safety, UTF-8 normalization, trace linkage.
  # Reads: @role, @model_name, @delegation_contract, @delegation_contract_source, @context, @debug
  module Observability
    private

    def _build_log_entry(log_context)
      entry = _base_log_entry(log_context)
      _add_contract_to_entry(entry)
      _add_outcome_to_entry(entry, log_context[:outcome]) if log_context[:outcome]
      _add_error_to_entry(entry, log_context[:error]) if log_context[:error]
      _add_debug_section(entry, log_context) if @debug
      entry
    end

    def _base_log_entry(log_context)
      {
        timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
        runtime: Agent::RUNTIME_NAME,
        role: @role,
        model: @model_name,
        method: log_context[:method_name],
        args: log_context[:args],
        kwargs: log_context[:kwargs],
        contract_source: @delegation_contract_source,
        code: log_context[:code],
        program_dependencies: log_context[:program_dependencies],
        normalized_dependencies: log_context[:normalized_dependencies],
        duration_ms: log_context[:duration_ms].round(1),
        generation_attempt: log_context[:generation_attempt]
      }.merge(_trace_log_fields(log_context)).merge(_environment_log_fields(log_context))
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
        log_context[:error]
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
      entry[:outcome_status] = outcome.status
      entry[:outcome_retriable] = outcome.retriable
      entry[:outcome_specialist_role] = outcome.specialist_role
      entry[:outcome_method_name] = outcome.method_name
      if outcome.ok?
        entry[:outcome_value_class] = outcome.value.class.name unless outcome.value.nil?
        entry[:outcome_value] = _debug_serializable_value(outcome.value) if @debug
      else
        entry[:outcome_error_type] = outcome.error_type
        entry[:outcome_error_message] = outcome.error_message
      end
    end

    def _add_debug_to_entry(entry, system_prompt, user_prompt, error)
      entry[:system_prompt] = system_prompt
      entry[:user_prompt] = user_prompt
      entry[:context] = @context.dup
      entry[:error_backtrace] = error.backtrace&.first(10) if error
    end

    # Keep debug logs robust when runtime values are not JSON-friendly.
    def _debug_serializable_value(value)
      JSON.parse(JSON.generate(value))
    rescue JSON::GeneratorError, TypeError
      value.inspect
    end
  end
end
