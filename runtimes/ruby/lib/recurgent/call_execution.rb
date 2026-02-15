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
      frame = {
        trace_id: @trace_id,
        call_id: SecureRandom.hex(8),
        parent_call_id: _call_stack.last&.fetch(:call_id, nil),
        depth: _call_stack.length
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
    rescue ProviderError, ExecutionError, BudgetExceededError, WorkerCrashError, NonSerializableResultError => e
      state.error = e
      state.outcome = _error_outcome_for(name, e)
      state.outcome
    ensure
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000
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
      generated_program, state.generation_attempt = _generate_program_with_retry(name, system_prompt, user_prompt) do |attempt_number|
        state.generation_attempt = attempt_number
      end
      _capture_generated_program_state!(state, generated_program)
      environment_info = _prepare_dependency_environment!(
        method_name: name,
        normalized_dependencies: state.normalized_dependencies
      )
      _capture_environment_state!(state, environment_info)
      _execute_generated_program(
        name,
        state.code,
        args,
        kwargs,
        normalized_dependencies: state.normalized_dependencies,
        environment_info: environment_info,
        state: state
      )
    end

    def _execute_generated_program(name, code, args, kwargs, normalized_dependencies:, environment_info:, state:)
      _print_generated_code(name, code) if @verbose

      if _worker_execution_required?(normalized_dependencies)
        return _execute_generated_program_in_worker(
          name,
          code,
          args,
          kwargs,
          environment_info: environment_info,
          state: state
        )
      end

      result = _execute_code(code, name, *args, **kwargs)
      Outcome.coerce(result, tool_role: @role, method_name: name)
    end

    def _print_generated_code(name, code)
      puts "[AGENT #{@role}.#{name}] Generated code:"
      puts "=" * 50
      puts code
      puts "=" * 50
    end
  end
end
