# frozen_string_literal: true

class Agent
  CallState = Struct.new(
    :code, :program_dependencies, :normalized_dependencies,
    :env_id, :environment_cache_hit, :env_prepare_ms, :env_resolve_ms, :env_install_ms,
    :worker_pid, :worker_restart_count,
    :program_source, :artifact_hit, :artifact_prompt_version, :artifact_contract_fingerprint,
    :artifact_selected_checksum, :artifact_selected_lifecycle_state,
    :cacheable, :cacheability_reason, :input_sensitive,
    :capability_patterns, :capability_pattern_evidence,
    :solver_shape, :solver_shape_complete,
    :self_model, :awareness_level, :authority,
    :active_contract_version, :active_role_profile_version,
    :role_profile_compliance, :role_profile_violation_count, :role_profile_violation_types,
    :role_profile_correction_hint, :role_profile_shadow_mode, :role_profile_enforced,
    :execution_snapshot_ref, :evolution_snapshot_ref,
    :namespace_key_collision_count, :namespace_multi_lifetime_key_count, :namespace_continuity_violation_count,
    :promotion_policy_version, :lifecycle_state, :lifecycle_decision,
    :promotion_decision_rationale, :promotion_shadow_mode, :promotion_enforced,
    :history_record_appended, :conversation_history_size,
    :content_store_write_applied, :content_store_write_ref, :content_store_write_kind,
    :content_store_write_bytes, :content_store_write_digest, :content_store_write_skipped_reason,
    :content_store_eviction_count,
    :content_store_read_hit_count, :content_store_read_miss_count, :content_store_read_refs,
    :content_store_entry_count, :content_store_total_bytes,
    :history_access_detected, :history_query_patterns,
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
      artifact_selected_checksum: nil,
      artifact_selected_lifecycle_state: nil,
      cacheable: false,
      cacheability_reason: "unknown",
      input_sensitive: false,
      capability_patterns: [],
      capability_pattern_evidence: {},
      solver_shape: {},
      solver_shape_complete: false,
      self_model: {},
      awareness_level: "l1",
      authority: _awareness_default_authority,
      active_contract_version: nil,
      active_role_profile_version: nil,
      role_profile_compliance: nil,
      role_profile_violation_count: 0,
      role_profile_violation_types: [],
      role_profile_correction_hint: nil,
      role_profile_shadow_mode: false,
      role_profile_enforced: false,
      execution_snapshot_ref: nil,
      evolution_snapshot_ref: nil,
      namespace_key_collision_count: 0,
      namespace_multi_lifetime_key_count: 0,
      namespace_continuity_violation_count: 0,
      promotion_policy_version: nil,
      lifecycle_state: nil,
      lifecycle_decision: nil,
      promotion_decision_rationale: {},
      promotion_shadow_mode: false,
      promotion_enforced: false,
      history_record_appended: false,
      conversation_history_size: 0,
      content_store_write_applied: false,
      content_store_write_ref: nil,
      content_store_write_kind: nil,
      content_store_write_bytes: nil,
      content_store_write_digest: nil,
      content_store_write_skipped_reason: nil,
      content_store_eviction_count: 0,
      content_store_read_hit_count: 0,
      content_store_read_miss_count: 0,
      content_store_read_refs: [],
      content_store_entry_count: 0,
      content_store_total_bytes: 0,
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

  def _capture_awareness_state!(state, method_name:, call_context:)
    active_contract_version = _active_contract_version
    active_role_profile_version = _active_role_profile_version
    evolution_snapshot_ref = _awareness_evolution_snapshot_ref(method_name: method_name, state: state)
    awareness_level = _awareness_level(
      active_contract_version: active_contract_version,
      active_role_profile_version: active_role_profile_version,
      evolution_snapshot_ref: evolution_snapshot_ref,
      state: state
    )
    execution_snapshot_ref = _awareness_execution_snapshot_ref(method_name: method_name, call_context: call_context)

    state.awareness_level = awareness_level
    state.authority = _awareness_default_authority
    state.active_contract_version = active_contract_version
    state.active_role_profile_version = active_role_profile_version
    state.execution_snapshot_ref = execution_snapshot_ref
    state.evolution_snapshot_ref = evolution_snapshot_ref
    state.self_model = _build_self_model(state)
  end

  def _finalize_awareness_state!(state, method_name:, call_context:)
    _capture_awareness_state!(state, method_name: method_name, call_context: call_context)
    @self_model = state.self_model
  end

  def _capture_solver_shape_state!(state, method_name:, args:, kwargs:, call_context:)
    depth = call_context&.fetch(:depth, 0).to_i
    solver_shape = {
      stance: _solver_shape_stance(method_name: method_name, depth: depth),
      capability_summary: _solver_shape_capability_summary(method_name: method_name, args: args, kwargs: kwargs),
      reuse_basis: _solver_shape_initial_reuse_basis(method_name: method_name, depth: depth),
      contract_intent: _solver_shape_contract_intent(method_name: method_name),
      promotion_intent: _solver_shape_promotion_intent(method_name: method_name, depth: depth)
    }
    state.solver_shape = solver_shape
    state.solver_shape_complete = _solver_shape_complete?(solver_shape)
  end

  def _finalize_solver_shape_state!(state)
    shape = state.solver_shape.is_a?(Hash) ? state.solver_shape.dup : {}
    shape[:reuse_basis] = _solver_shape_runtime_reuse_basis(state, default: shape[:reuse_basis])
    state.solver_shape = shape
    state.solver_shape_complete = _solver_shape_complete?(shape)
  end

  def _solver_shape_stance(method_name:, depth:)
    return "do" if depth >= 1
    return "forge" if _dynamic_dispatch_method?(method_name)
    return "do" unless @delegation_contract.nil?

    "shape"
  end

  def _solver_shape_capability_summary(method_name:, args:, kwargs:)
    role = @role.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    method = method_name.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    arg_count = Array(args).length
    kwarg_count = kwargs.length
    [role, method, "args#{arg_count}", "kwargs#{kwarg_count}"].join(".")
  end

  def _solver_shape_initial_reuse_basis(method_name:, depth:)
    return "delegated_execution_depth_#{depth}" if depth >= 1
    return "dynamic_dispatch_method" if _dynamic_dispatch_method?(method_name)

    "direct_method_dispatch"
  end

  def _solver_shape_runtime_reuse_basis(state, default:)
    return "persisted_artifact_reuse" if state.artifact_hit == true
    return "repaired_artifact_execution" if state.program_source.to_s == "repaired"
    return "generated_program_fresh" if state.program_source.to_s == "generated"

    default || "unknown"
  end

  def _solver_shape_contract_intent(method_name:)
    return _solver_shape_explicit_contract_intent unless @delegation_contract.nil?

    {
      purpose: "resolve #{@role}.#{method_name}",
      failure_policy: { on_error: "return_error" }
    }
  end

  def _solver_shape_explicit_contract_intent
    {
      purpose: @delegation_contract[:purpose] || @delegation_contract["purpose"] || "unspecified",
      deliverable: @delegation_contract[:deliverable] || @delegation_contract["deliverable"],
      acceptance: @delegation_contract[:acceptance] || @delegation_contract["acceptance"],
      failure_policy: @delegation_contract[:failure_policy] || @delegation_contract["failure_policy"] || {}
    }.compact
  end

  def _solver_shape_promotion_intent(method_name:, depth:)
    return "none" unless depth.zero?
    return "durable_tool_candidate" if _dynamic_dispatch_method?(method_name)
    return "none" if method_name.to_s == "to_s"

    "local_pattern"
  end

  def _solver_shape_complete?(shape)
    return false unless shape.is_a?(Hash)

    required = %i[stance contract_intent promotion_intent]
    required.all? do |key|
      value = shape[key] || shape[key.to_s]
      case value
      when nil
        false
      when String
        !value.strip.empty?
      when Hash
        !value.empty?
      else
        true
      end
    end
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

  def _awareness_default_authority
    {
      observe: true,
      propose: true,
      enact: false
    }
  end

  def _active_contract_version
    contract = @delegation_contract
    return nil unless contract.is_a?(Hash)

    contract[:version] || contract["version"] || contract[:contract_version] || contract["contract_version"]
  end

  def _active_role_profile_version
    profile = _active_role_profile
    return nil unless profile

    profile[:version] || profile["version"] || profile[:profile_version] || profile["profile_version"]
  end

  def _awareness_execution_snapshot_ref(method_name:, call_context:)
    trace_id = call_context&.fetch(:trace_id, nil).to_s
    call_id = call_context&.fetch(:call_id, nil).to_s
    method = method_name.to_s
    return nil if trace_id.empty? || call_id.empty? || method.empty?

    "#{trace_id}:#{call_id}:#{@role}.#{method}"
  end

  def _awareness_evolution_snapshot_ref(method_name:, state:)
    method = method_name.to_s
    checksum = state.artifact_selected_checksum.to_s
    checksum = _artifact_code_checksum(state.code.to_s) if checksum.empty? && !state.code.to_s.strip.empty?
    return nil if method.empty? && checksum.empty?
    return nil if checksum.empty? && state.lifecycle_state.to_s.empty?

    identity = "#{@role}.#{method}"
    return "#{identity}@#{checksum}" unless checksum.empty?

    "#{identity}:#{state.lifecycle_state}"
  end

  def _awareness_level(active_contract_version:, active_role_profile_version:, evolution_snapshot_ref:, state:)
    has_contract = !active_contract_version.nil? || !active_role_profile_version.nil?
    has_evolution = !evolution_snapshot_ref.nil? || !state.lifecycle_state.nil? || !state.promotion_policy_version.nil?
    return "l3" if has_evolution
    return "l2" if has_contract

    "l1"
  end

  def _build_self_model(state)
    {
      awareness_level: state.awareness_level || "l1",
      authority: state.authority || _awareness_default_authority,
      active_contract_version: state.active_contract_version,
      active_role_profile_version: state.active_role_profile_version,
      execution_snapshot_ref: state.execution_snapshot_ref,
      evolution_snapshot_ref: state.evolution_snapshot_ref
    }
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

    arg_ignored = _input_args_ignored?(code, args: args, kwargs: kwargs)
    return _cacheability(false, "arg_ignored_code", input_sensitive: true) if arg_ignored

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

  def _input_args_ignored?(code, args:, kwargs:)
    return false if Array(args).empty? && kwargs.empty?
    return false if code.match?(/\bargs\b|\bkwargs\b/)

    code.match?(/(?:\bcontext\b|\bmemory\b)\s*\[/)
  end

  def _input_literals(args:, kwargs:)
    values = Array(args) + kwargs.values
    values.flat_map { |value| _literal_candidates(value) }.reject(&:empty?).uniq
  end

  def _literal_candidates(value)
    unwrapped = value.is_a?(Agent::Outcome) ? value.value : value
    collection = _nested_literal_candidates(unwrapped)
    return collection unless collection.nil?

    literal = _scalar_literal(unwrapped)
    return [] if literal.nil? || literal.empty?

    [literal]
  end

  def _nested_literal_candidates(value)
    return value.flat_map { |item| _literal_candidates(item) } if value.is_a?(Array)
    return value.values.flat_map { |item| _literal_candidates(item) } if value.is_a?(Hash)

    nil
  end

  def _scalar_literal(value)
    case value
    when String
      value.strip
    when Symbol, Integer, Float, TrueClass, FalseClass
      value.to_s
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
