# frozen_string_literal: true

class Agent
  CallState = Struct.new(
    :code, :program_dependencies, :normalized_dependencies,
    :env_id, :environment_cache_hit, :env_prepare_ms, :env_resolve_ms, :env_install_ms,
    :worker_pid, :worker_restart_count,
    :program_source, :artifact_hit, :artifact_prompt_version, :artifact_contract_fingerprint,
    :cacheable, :cacheability_reason, :input_sensitive,
    :capability_patterns, :capability_pattern_evidence,
    :history_record_appended, :conversation_history_size, :history_access_detected, :history_query_patterns,
    :user_correction_detected, :user_correction_signal, :user_correction_reference_call_id,
    :contract_validation_applied, :contract_validation_passed,
    :contract_validation_mismatch, :contract_validation_expected_keys, :contract_validation_actual_keys,
    :artifact_generation_trigger,
    :attempt_id, :attempt_stage, :validation_failure_type, :rollback_applied, :retry_feedback_injected,
    :attempt_failures, :latest_failure_stage, :latest_failure_class, :latest_failure_message,
    :execution_receiver,
    :guardrail_violation_subtype,
    :guardrail_recovery_attempts, :execution_repair_attempts, :outcome_repair_attempts,
    :outcome_repair_triggered, :guardrail_retry_exhausted, :outcome_repair_retry_exhausted,
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
      cacheable: false,
      cacheability_reason: "unknown",
      input_sensitive: false,
      capability_patterns: [],
      capability_pattern_evidence: {},
      history_record_appended: false,
      conversation_history_size: 0,
      history_access_detected: false,
      history_query_patterns: [],
      user_correction_detected: false,
      user_correction_signal: nil,
      user_correction_reference_call_id: nil,
      contract_validation_applied: false,
      contract_validation_passed: nil,
      contract_validation_mismatch: nil,
      contract_validation_expected_keys: [],
      contract_validation_actual_keys: [],
      attempt_id: 1,
      attempt_stage: nil,
      validation_failure_type: nil,
      rollback_applied: false,
      retry_feedback_injected: false,
      attempt_failures: [],
      latest_failure_stage: nil,
      latest_failure_class: nil,
      latest_failure_message: nil,
      execution_receiver: nil,
      guardrail_violation_subtype: nil,
      guardrail_recovery_attempts: 0,
      execution_repair_attempts: 0,
      outcome_repair_attempts: 0,
      outcome_repair_triggered: false,
      guardrail_retry_exhausted: false,
      outcome_repair_retry_exhausted: false,
      repair_attempted: false,
      repair_succeeded: false
    )
  end

  def _capture_generated_program_state!(state, generated_program, method_name:, args:, kwargs:)
    state.code = generated_program.code
    state.program_dependencies = generated_program.program_dependencies
    state.normalized_dependencies = generated_program.normalized_dependencies
    state.program_source = "generated"
    state.artifact_hit = false
    _capture_cacheability_state!(state, method_name: method_name, args: args, kwargs: kwargs)
    _capture_capability_pattern_state!(state, method_name: method_name, args: args, kwargs: kwargs)
    _capture_history_usage_state!(state)
    state.artifact_generation_trigger = nil
  end

  def _capture_persisted_artifact_state!(state, artifact)
    state.code = artifact.fetch("code")
    state.program_dependencies = artifact.fetch("dependencies", [])
    state.normalized_dependencies = DependencyManifest.normalize!(state.program_dependencies)
    state.program_source = "persisted"
    state.artifact_hit = true
    _capture_persisted_artifact_metadata!(state, artifact)
    state.capability_patterns = []
    state.capability_pattern_evidence = {}
    state.artifact_generation_trigger = nil
  end

  def _capture_persisted_artifact_metadata!(state, artifact)
    state.artifact_prompt_version = artifact["prompt_version"]
    state.artifact_contract_fingerprint = artifact["contract_fingerprint"]
    state.cacheable = artifact["cacheable"] == true
    state.cacheability_reason = artifact["cacheability_reason"]
    state.input_sensitive = artifact["input_sensitive"] == true
    _capture_history_usage_state!(state)
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

  def _capture_cacheability_state!(state, method_name:, args:, kwargs:)
    classification = _classify_cacheability(method_name: method_name, args: args, kwargs: kwargs, code: state.code.to_s)
    state.cacheable = classification[:cacheable]
    state.cacheability_reason = classification[:reason]
    state.input_sensitive = classification[:input_sensitive]
  end

  def _capture_capability_pattern_state!(state, method_name:, args:, kwargs:)
    extraction = _extract_capability_patterns(
      method_name: method_name,
      role: @role,
      code: state.code.to_s,
      args: args,
      kwargs: kwargs,
      outcome: state.outcome,
      program_source: state.program_source
    )
    state.capability_patterns = extraction[:patterns]
    state.capability_pattern_evidence = extraction[:evidence]
  end

  def _capture_history_usage_state!(state)
    detection = _detect_conversation_history_usage(state.code.to_s)
    state.history_access_detected = detection[:accessed]
    state.history_query_patterns = detection[:patterns]
  end

  def _detect_conversation_history_usage(code)
    return { accessed: false, patterns: [] } unless code.match?(/conversation_history/)

    patterns = []
    patterns << "filter" if code.match?(/\.(select|filter|reject|find_all)\b/)
    patterns << "map" if code.match?(/\.(map|collect)\b/)
    patterns << "slice" if code.match?(/(\.slice\(|\[\s*\d+\s*\.\.\s*\d*\s*\]|\.take\(|\.drop\()/)
    patterns << "count" if code.match?(/\.(count|length|size)\b/)
    patterns << "group" if code.match?(/\.(group_by|chunk)\b/)

    { accessed: true, patterns: patterns.uniq }
  end

  def _classify_cacheability(method_name:, args:, kwargs:, code:)
    return _cacheability(false, "dynamic_dispatch_method", input_sensitive: true) if _dynamic_dispatch_method?(method_name)

    input_sensitive = _input_baked_into_code?(code, args: args, kwargs: kwargs)
    return _cacheability(false, "input_baked_code", input_sensitive: true) if input_sensitive

    return _cacheability(true, "delegated_contract_tool", input_sensitive: false) unless @delegation_contract.nil?

    _cacheability(true, "stable_method_default", input_sensitive: false)
  end

  def _dynamic_dispatch_method?(method_name)
    Agent::DYNAMIC_DISPATCH_METHODS.include?(method_name.to_s.downcase)
  end

  def _input_baked_into_code?(code, args:, kwargs:)
    return false if Array(args).empty? && kwargs.empty?
    return false if code.match?(/\bargs\b|\bkwargs\b/)

    _input_literals(args: args, kwargs: kwargs).any? { |literal| !literal.empty? && code.include?(literal) }
  end

  def _input_literals(args:, kwargs:)
    values = Array(args) + kwargs.values
    values.flat_map { |value| _literal_candidates(value) }.reject(&:empty?).uniq
  end

  def _literal_candidates(value)
    case value
    when Agent::Outcome
      _literal_candidates(value.value)
    when Array
      value.flat_map { |item| _literal_candidates(item) }
    when Hash
      value.values.flat_map { |item| _literal_candidates(item) }
    when String
      [value.strip]
    when Symbol, Integer, Float, TrueClass, FalseClass
      [value.to_s]
    else
      []
    end
  end

  def _cacheability(cacheable, reason, input_sensitive:)
    {
      cacheable: cacheable,
      reason: reason,
      input_sensitive: input_sensitive
    }
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
