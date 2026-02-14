# frozen_string_literal: true

class Agent
  CallState = Struct.new(
    :code, :program_dependencies, :normalized_dependencies,
    :env_id, :environment_cache_hit, :env_prepare_ms, :env_resolve_ms, :env_install_ms,
    :worker_pid, :worker_restart_count,
    :generation_attempt, :error, :outcome,
    keyword_init: true
  )

  private

  def _initial_call_state
    CallState.new(generation_attempt: 0)
  end

  def _capture_generated_program_state!(state, generated_program)
    state.code = generated_program.code
    state.program_dependencies = generated_program.program_dependencies
    state.normalized_dependencies = generated_program.normalized_dependencies
  end

  def _capture_environment_state!(state, environment_info)
    state.env_id = environment_info[:env_id]
    state.environment_cache_hit = environment_info[:environment_cache_hit]
    state.env_prepare_ms = environment_info[:env_prepare_ms]
    state.env_resolve_ms = environment_info[:env_resolve_ms]
    state.env_install_ms = environment_info[:env_install_ms]
  end

  def _log_dynamic_call(method_name:, args:, kwargs:, duration_ms:, system_prompt:, user_prompt:, call_context:, state:)
    _log_call(
      **state.to_h,
      method_name: method_name,
      args: args,
      kwargs: kwargs,
      prep_ticket_id: @prep_ticket_id,
      duration_ms: duration_ms,
      system_prompt: system_prompt,
      user_prompt: user_prompt,
      call_context: call_context
    )
  end
end
