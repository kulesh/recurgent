# frozen_string_literal: true

class Agent
  # Agent::CallExecution — orchestration for dynamic calls, execution path selection, and trace frame linkage.
  module CallExecution
    private

    # The main dispatch: build prompts, ask LLM for code, execute it.
    # Only handles method calls — setters are handled directly in method_missing.
    def _dispatch_method_call(name, *args, **kwargs)
      _with_call_frame do |call_context|
        system_prompt = _build_system_prompt(call_context: call_context)
        user_prompt = _build_user_prompt(name, args, kwargs, call_context: call_context)
        _execute_dynamic_call(name, args, kwargs, system_prompt, user_prompt, call_context)
      end
    end

    def _call_stack
      Thread.current[CALL_STACK_KEY] ||= []
    end

    def _with_call_frame
      parent_frame = _call_stack.last
      parent_frame[:had_child_calls] = true if parent_frame

      frame = {
        trace_id: @trace_id,
        call_id: SecureRandom.hex(8),
        parent_call_id: parent_frame&.fetch(:call_id, nil),
        depth: _call_stack.length,
        had_child_calls: false
      }
      _call_stack.push(frame)
      yield frame
    ensure
      _call_stack.pop
    end

    def _execute_dynamic_call(name, args, kwargs, system_prompt, user_prompt, call_context)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      state = _initial_call_state

      state.outcome = _generate_and_execute(name, args, kwargs, system_prompt, user_prompt, state)
      state.outcome
    rescue ProviderError, ExecutionError, ToolRegistryViolationError, GuardrailRetryExhaustedError, BudgetExceededError, WorkerCrashError,
           NonSerializableResultError => e
      state.error = e
      state.outcome = _error_outcome_for(name, e)
      state.outcome
    ensure
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000
      history_append = _append_conversation_history_record!(
        method_name: name,
        args: args,
        kwargs: kwargs,
        duration_ms: duration_ms,
        call_context: call_context,
        outcome: state.outcome
      )
      state.history_record_appended = history_append[:appended]
      state.conversation_history_size = history_append[:size]
      _record_pattern_memory_event(method_name: name, state: state, call_context: call_context)
      _persist_method_artifact_for_call(method_name: name, state: state, duration_ms: duration_ms)
      _log_dynamic_call(
        method_name: name,
        args: args,
        kwargs: kwargs,
        duration_ms: duration_ms,
        system_prompt: system_prompt,
        user_prompt: user_prompt,
        call_context: call_context,
        state: state
      )
    end

    def _generate_and_execute(name, args, kwargs, system_prompt, user_prompt, state)
      persisted_outcome = _try_persisted_artifact_execution(name, args, kwargs, state)
      return persisted_outcome unless persisted_outcome.nil?

      _generate_and_execute_fresh(name, args, kwargs, system_prompt, user_prompt, state)
    end

    def _execute_generated_program(name, code, args, kwargs, normalized_dependencies:, environment_info:, state:)
      _print_generated_code(name, code) if @verbose

      outcome =
        if _worker_execution_required?(normalized_dependencies)
          _execute_generated_program_in_worker(
            name,
            code,
            args,
            kwargs,
            environment_info: environment_info,
            state: state
          )
        else
          result = _execute_code(code, name, *args, **kwargs)
          Outcome.coerce(result, tool_role: @role, method_name: name)
        end

      _validate_delegated_outcome_contract(
        outcome: outcome,
        method_name: name,
        args: args,
        kwargs: kwargs,
        state: state
      )
    end

    def _print_generated_code(name, code)
      puts "[AGENT #{@role}.#{name}] Generated code:"
      puts "=" * 50
      puts code
      puts "=" * 50
    end
  end
end
