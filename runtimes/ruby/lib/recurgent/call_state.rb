# frozen_string_literal: true

class Agent
  CallState = Struct.new(
    :code, :program_dependencies, :normalized_dependencies,
    :env_id, :environment_cache_hit, :env_prepare_ms, :env_resolve_ms, :env_install_ms,
    :worker_pid, :worker_restart_count,
    :program_source, :artifact_hit, :artifact_prompt_version, :artifact_contract_fingerprint,
    :artifact_generation_trigger,
    :repair_attempted, :repair_succeeded, :failure_class,
    :generation_attempt, :error, :outcome,
    keyword_init: true
  )

  private

  def _initial_call_state
    CallState.new(
      generation_attempt: 0,
      program_source: "generated",
      artifact_hit: false,
      repair_attempted: false,
      repair_succeeded: false
    )
  end

  def _capture_generated_program_state!(state, generated_program)
    state.code = generated_program.code
    state.program_dependencies = generated_program.program_dependencies
    state.normalized_dependencies = generated_program.normalized_dependencies
    state.program_source = "generated"
    state.artifact_hit = false
    state.artifact_generation_trigger = nil
  end

  def _capture_persisted_artifact_state!(state, artifact)
    state.code = artifact.fetch("code")
    state.program_dependencies = artifact.fetch("dependencies", [])
    state.normalized_dependencies = DependencyManifest.normalize!(state.program_dependencies)
    state.program_source = "persisted"
    state.artifact_hit = true
    state.artifact_prompt_version = artifact["prompt_version"]
    state.artifact_contract_fingerprint = artifact["contract_fingerprint"]
    state.artifact_generation_trigger = nil
  end

  def _mark_repaired_program_state!(state, trigger:)
    state.program_source = "repaired"
    state.repair_succeeded = true
    state.artifact_generation_trigger = trigger
  end

  def _capture_environment_state!(state, environment_info)
    effective_manifest = environment_info[:effective_manifest]
    state.normalized_dependencies = effective_manifest unless effective_manifest.nil?
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
