# frozen_string_literal: true

class Agent
  private

  def _initial_dynamic_call_state
    {
      code: nil,
      program_dependencies: nil,
      normalized_dependencies: nil,
      env_id: nil,
      environment_cache_hit: nil,
      env_prepare_ms: nil,
      env_resolve_ms: nil,
      env_install_ms: nil,
      worker_pid: nil,
      worker_restart_count: nil,
      generation_attempt: 0,
      error: nil,
      outcome: nil
    }
  end

  def _capture_generated_program_state!(state, generated_program)
    state[:code] = generated_program.code
    state[:program_dependencies] = generated_program.program_dependencies
    state[:normalized_dependencies] = generated_program.normalized_dependencies
  end

  def _capture_environment_state!(state, environment_info)
    state[:env_id] = environment_info[:env_id]
    state[:environment_cache_hit] = environment_info[:environment_cache_hit]
    state[:env_prepare_ms] = environment_info[:env_prepare_ms]
    state[:env_resolve_ms] = environment_info[:env_resolve_ms]
    state[:env_install_ms] = environment_info[:env_install_ms]
  end

  def _log_dynamic_call(method_name:, args:, kwargs:, duration_ms:, system_prompt:, user_prompt:, call_context:, state:)
    _log_call(
      method_name: method_name,
      args: args,
      kwargs: kwargs,
      code: state[:code],
      program_dependencies: state[:program_dependencies],
      normalized_dependencies: state[:normalized_dependencies],
      env_id: state[:env_id],
      environment_cache_hit: state[:environment_cache_hit],
      env_prepare_ms: state[:env_prepare_ms],
      env_resolve_ms: state[:env_resolve_ms],
      env_install_ms: state[:env_install_ms],
      worker_pid: state[:worker_pid],
      worker_restart_count: state[:worker_restart_count],
      prep_ticket_id: @prep_ticket_id,
      duration_ms: duration_ms,
      generation_attempt: state[:generation_attempt],
      system_prompt: system_prompt,
      user_prompt: user_prompt,
      outcome: state[:outcome],
      error: state[:error],
      call_context: call_context
    )
  end
end
