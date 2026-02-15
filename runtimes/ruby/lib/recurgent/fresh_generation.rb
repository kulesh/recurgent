# frozen_string_literal: true

class Agent
  # Agent::FreshGeneration — validation-first fresh-generation loop with guardrail recovery.
  module FreshGeneration
    FRESH_EXECUTION_REPAIR_BUDGET = 1

    private

    def _generate_and_execute_fresh(name, args, kwargs, system_prompt, user_prompt, state)
      guardrail_feedback = nil
      execution_feedback = nil
      guardrail_recovery_attempts = 0
      execution_repair_attempts = 0

      loop do
        input = _fresh_attempt_input(args: args, kwargs: kwargs, system_prompt: system_prompt, user_prompt: user_prompt)
        retry_state = _fresh_retry_state(guardrail_feedback: guardrail_feedback, execution_feedback: execution_feedback,
                                         guardrail_recovery_attempts: guardrail_recovery_attempts,
                                         execution_repair_attempts: execution_repair_attempts)
        environment_info = _prepare_fresh_generation_attempt!(method_name: name, state: state, input: input, retry_state: retry_state)
        attempt_snapshot = _capture_attempt_snapshot
        outcome, guardrail_feedback, execution_feedback, guardrail_recovery_attempts, execution_repair_attempts =
          _execute_fresh_attempt_or_prepare_retry(
            method_name: name,
            args: args,
            kwargs: kwargs,
            state: state,
            environment_info: environment_info,
            attempt_snapshot: attempt_snapshot,
            guardrail_recovery_attempts: guardrail_recovery_attempts,
            execution_repair_attempts: execution_repair_attempts
          )
        return outcome unless outcome.nil?
      end
    end

    def _prepare_fresh_generation_attempt!(
      method_name:,
      state:,
      input:,
      retry_state:
    )
      context = _fresh_attempt_context(input: input, retry_state: retry_state)
      args = context[:args]
      kwargs = context[:kwargs]
      system_prompt = context[:system_prompt]
      user_prompt = context[:user_prompt]
      guardrail_feedback = context[:guardrail_feedback]
      execution_feedback = context[:execution_feedback]
      _reset_fresh_attempt_state!(state, context: context)

      attempt_user_prompt = _fresh_retry_user_prompt(
        user_prompt,
        guardrail_feedback: guardrail_feedback,
        execution_feedback: execution_feedback
      )
      generated_program, state.generation_attempt = _generate_program_with_retry(method_name, system_prompt, attempt_user_prompt) do |attempt_number|
        state.generation_attempt = attempt_number
      end
      _capture_generated_program_state!(
        state,
        generated_program,
        method_name: method_name,
        args: args,
        kwargs: kwargs
      )
      state.attempt_stage = "generated"

      environment_info = _prepare_dependency_environment!(
        method_name: method_name,
        normalized_dependencies: state.normalized_dependencies
      )
      _capture_environment_state!(state, environment_info)
      environment_info
    end

    def _execute_fresh_attempt_or_prepare_retry(
      method_name:,
      args:,
      kwargs:,
      state:,
      environment_info:,
      attempt_snapshot:,
      guardrail_recovery_attempts:,
      execution_repair_attempts:
    )
      _validate_generated_code_policy!(method_name, state.code)
      state.attempt_stage = "validated"
      outcome = _execute_generated_program(
        method_name,
        state.code,
        args,
        kwargs,
        normalized_dependencies: state.normalized_dependencies,
        environment_info: environment_info,
        state: state
      )
      state.attempt_stage = "executed"
      state.guardrail_recovery_attempts = guardrail_recovery_attempts
      state.execution_repair_attempts = execution_repair_attempts
      [outcome, nil, nil, guardrail_recovery_attempts, execution_repair_attempts]
    rescue ToolRegistryViolationError => e
      _handle_guardrail_retry(
        method_name: method_name,
        state: state,
        attempt_snapshot: attempt_snapshot,
        error: e,
        guardrail_recovery_attempts: guardrail_recovery_attempts,
        execution_repair_attempts: execution_repair_attempts
      )
    rescue ExecutionError, WorkerCrashError, NonSerializableResultError => e
      _handle_execution_retry(
        state: state,
        attempt_snapshot: attempt_snapshot,
        error: e,
        guardrail_recovery_attempts: guardrail_recovery_attempts,
        execution_repair_attempts: execution_repair_attempts
      )
    end

    def _fresh_attempt_input(args:, kwargs:, system_prompt:, user_prompt:)
      { args: args, kwargs: kwargs, system_prompt: system_prompt, user_prompt: user_prompt }
    end

    def _fresh_retry_state(guardrail_feedback:, execution_feedback:, guardrail_recovery_attempts:, execution_repair_attempts:)
      {
        guardrail_feedback: guardrail_feedback,
        execution_feedback: execution_feedback,
        guardrail_recovery_attempts: guardrail_recovery_attempts,
        execution_repair_attempts: execution_repair_attempts
      }
    end

    def _fresh_attempt_context(input:, retry_state:)
      input.merge(retry_state).merge(
        attempt_id: retry_state[:guardrail_recovery_attempts] + retry_state[:execution_repair_attempts] + 1
      )
    end

    def _reset_fresh_attempt_state!(state, context:)
      state.attempt_id = context[:attempt_id]
      state.retry_feedback_injected = !context[:guardrail_feedback].nil? || !context[:execution_feedback].nil?
      state.validation_failure_type = nil
      state.rollback_applied = false
      state.execution_repair_attempts = context[:execution_repair_attempts]
    end

    def _handle_guardrail_retry(method_name:, state:, attempt_snapshot:, error:, guardrail_recovery_attempts:, execution_repair_attempts:)
      _restore_attempt_snapshot!(attempt_snapshot)
      _apply_guardrail_failure_state!(state, error)
      classification = _classify_guardrail_violation(error)
      raise if classification[:guardrail_class] == "terminal_guardrail"

      next_feedback, next_attempts = _next_guardrail_retry_feedback!(
        method_name: method_name,
        state: state,
        classification: classification,
        guardrail_recovery_attempts: guardrail_recovery_attempts
      )
      [nil, next_feedback, nil, next_attempts, execution_repair_attempts]
    end

    def _handle_execution_retry(state:, attempt_snapshot:, error:, guardrail_recovery_attempts:, execution_repair_attempts:)
      _restore_attempt_snapshot!(attempt_snapshot)
      state.rollback_applied = true
      state.attempt_stage = "execution_retry"
      state.validation_failure_type = _error_type_for_exception(error)

      classification = _classify_execution_failure(error)
      raise unless execution_repair_attempts < FRESH_EXECUTION_REPAIR_BUDGET

      next_attempts = execution_repair_attempts + 1
      state.execution_repair_attempts = next_attempts
      next_feedback = classification.merge(
        attempt_number: state.attempt_id + 1,
        remaining_budget: FRESH_EXECUTION_REPAIR_BUDGET - next_attempts
      )
      [nil, nil, next_feedback, guardrail_recovery_attempts, next_attempts]
    end
  end
end
