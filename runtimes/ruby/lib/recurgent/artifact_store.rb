# frozen_string_literal: true

require "digest"

class Agent
  # Agent::ArtifactStore — persisted generated-program artifacts: persistence, selection,
  # execution routing, repair, metrics, and trigger metadata.
  module ArtifactStore
    EXTRINSIC_FAILURE_TYPES = %w[
      timeout
      provider
      network_error
      rate_limit
      rate_limited
      environment_preparing
      worker_crash
      dependency_resolution_failed
      dependency_install_failed
      dependency_activation_failed
    ].freeze
    ADAPTIVE_FAILURE_TYPES = %w[
      parse_error
      parse_failed
      low_utility
      wrong_tool_boundary
      missing_input
      invalid_format
      schema_mismatch
      contract_violation
      guardrail_retry_exhausted
      outcome_repair_retry_exhausted
    ].freeze

    private

    # --- Persistence ---

    def _persist_method_artifact_for_call(method_name:, state:, duration_ms:)
      code = state.code.to_s
      return if code.strip.empty?

      timestamp = _artifact_timestamp
      artifact = _artifact_load(method_name) || _artifact_template(method_name)
      previous_checksum = artifact["code_checksum"]
      new_checksum = _artifact_code_checksum(code)

      _artifact_update_program_payload!(
        artifact,
        code: code,
        state: state,
        checksum: new_checksum,
        timestamp: timestamp
      )
      _artifact_update_metrics!(artifact, state)
      _artifact_update_generation_history!(
        artifact,
        state: state,
        previous_checksum: previous_checksum,
        new_checksum: new_checksum,
        timestamp: timestamp
      )

      artifact["last_used_at"] = timestamp
      artifact["last_duration_ms"] = duration_ms.round(1)
      _artifact_write(method_name, artifact)
      _toolstore_touch_tool_usage(@role, method_name: method_name, outcome: state.outcome)
    rescue StandardError => e
      warn "[AGENT ARTIFACT #{@role}.#{method_name}] failed to persist artifact: #{e.class}: #{e.message}" if @debug
    end

    def _artifact_template(method_name)
      {
        "schema_version" => Agent::TOOLSTORE_SCHEMA_VERSION,
        "role" => @role,
        "method_name" => method_name.to_s,
        "contract_fingerprint" => _artifact_contract_fingerprint,
        "prompt_version" => Agent::PROMPT_VERSION,
        "runtime_version" => Agent::VERSION,
        "model" => @model_name,
        "cacheable" => false,
        "cacheability_reason" => "unknown",
        "input_sensitive" => false,
        "code_checksum" => nil,
        "code" => "",
        "dependencies" => [],
        "success_count" => 0,
        "failure_count" => 0,
        "intrinsic_failure_count" => 0,
        "adaptive_failure_count" => 0,
        "extrinsic_failure_count" => 0,
        "recent_failure_rate" => 0.0,
        "last_failure_reason" => nil,
        "last_failure_class" => nil,
        "repair_count_since_regen" => 0,
        "created_at" => nil,
        "last_used_at" => nil,
        "last_repaired_at" => nil,
        "history" => []
      }
    end

    def _artifact_load(method_name)
      path = _toolstore_artifact_path(role_name: @role, method_name: method_name)
      return nil unless File.exist?(path)

      parsed = JSON.parse(File.read(path))
      return nil unless _artifact_schema_supported?(parsed["schema_version"])

      parsed
    rescue JSON::ParserError => e
      _artifact_quarantine_corrupt_file!(path, e)
      nil
    end

    def _artifact_write(method_name, artifact)
      path = _toolstore_artifact_path(role_name: @role, method_name: method_name)
      FileUtils.mkdir_p(File.dirname(path))
      payload = _json_safe(artifact)

      temp_path = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.write(temp_path, JSON.generate(payload))
      File.rename(temp_path, path)
    ensure
      File.delete(temp_path) if defined?(temp_path) && temp_path && File.exist?(temp_path)
    end

    def _artifact_schema_supported?(schema_version)
      return true if schema_version.nil?
      return true if schema_version.to_i == Agent::TOOLSTORE_SCHEMA_VERSION

      warn "[AGENT ARTIFACT #{@role}] ignored artifact schema=#{schema_version}" if @debug
      false
    end

    def _artifact_quarantine_corrupt_file!(path, error)
      return unless File.exist?(path)

      quarantined_path = "#{path}.corrupt-#{Time.now.utc.strftime("%Y%m%dT%H%M%S")}"
      FileUtils.mv(path, quarantined_path)
      return unless @debug

      warn(
        "[AGENT ARTIFACT #{@role}] quarantined corrupt artifact: #{File.basename(quarantined_path)} (#{error.class})"
      )
    rescue StandardError => e
      warn "[AGENT ARTIFACT #{@role}] failed to quarantine corrupt artifact: #{e.message}" if @debug
    end

    def _artifact_update_program_payload!(artifact, code:, state:, checksum:, timestamp:)
      artifact["role"] = @role
      artifact["method_name"] = artifact["method_name"].to_s
      artifact["contract_fingerprint"] = _artifact_contract_fingerprint
      artifact["prompt_version"] = Agent::PROMPT_VERSION
      artifact["runtime_version"] = Agent::VERSION
      artifact["model"] = @model_name
      artifact["cacheable"] = state.cacheable == true
      artifact["cacheability_reason"] = state.cacheability_reason
      artifact["input_sensitive"] = state.input_sensitive == true
      artifact["code_checksum"] = checksum
      artifact["code"] = code
      artifact["dependencies"] = state.program_dependencies || []
      artifact["created_at"] ||= timestamp
    end

    def _artifact_update_generation_history!(artifact, state:, previous_checksum:, new_checksum:, timestamp:)
      trigger = _artifact_generation_trigger(state, previous_checksum: previous_checksum)
      if trigger.start_with?("repair:")
        artifact["repair_count_since_regen"] = artifact["repair_count_since_regen"].to_i + 1
        artifact["last_repaired_at"] = timestamp
      elsif trigger.start_with?("regenerate:") || trigger == "initial_forge"
        artifact["repair_count_since_regen"] = 0
      end

      return if previous_checksum == new_checksum

      history = Array(artifact["history"])
      parent_id = history.first&.fetch("id", nil)
      entry = {
        "id" => "gen-#{SecureRandom.hex(6)}",
        "parent_id" => parent_id,
        "trigger" => trigger,
        "created_at" => timestamp,
        "code_checksum" => new_checksum,
        "prompt_version" => Agent::PROMPT_VERSION,
        "runtime_version" => Agent::VERSION,
        "model" => @model_name
      }
      entry.merge!(_artifact_trigger_failure_metadata(state))
      artifact["history"] = [entry, *history].first(3)
    end

    def _artifact_generation_trigger(state, previous_checksum:)
      explicit_trigger = state.artifact_generation_trigger.to_s
      return explicit_trigger unless explicit_trigger.empty?
      return "initial_forge" if previous_checksum.nil?

      "regenerate:new_code"
    end

    def _artifact_timestamp
      Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
    end

    def _artifact_code_checksum(code)
      "sha256:#{Digest::SHA256.hexdigest(code.to_s)}"
    end

    def _artifact_contract_fingerprint
      return "none" unless @delegation_contract

      normalized = _json_safe(@delegation_contract)
      "sha256:#{Digest::SHA256.hexdigest(JSON.generate(normalized))}"
    end

    # --- Artifact Selection ---

    def _select_persisted_artifact(method_name, state:)
      artifact = _artifact_load(method_name)
      return nil unless artifact
      return nil unless _artifact_cacheable_for_execution?(artifact, method_name: method_name)
      return nil unless _artifact_compatible_for_execution?(artifact)
      return nil if _artifact_degraded?(artifact)

      state.artifact_prompt_version = artifact["prompt_version"]
      state.artifact_contract_fingerprint = artifact["contract_fingerprint"]
      artifact
    end

    def _artifact_cacheable_for_execution?(artifact, method_name:)
      cacheable = artifact["cacheable"]
      return cacheable == true if [true, false].include?(cacheable)

      # Legacy artifacts (pre-cacheability metadata):
      # never reuse dynamic dispatch methods, allow stable method-level tools.
      return false if _dynamic_dispatch_method?(method_name)

      true
    end

    def _artifact_compatible_for_execution?(artifact)
      return false unless _artifact_runtime_compatible?(artifact)
      return false unless _artifact_contract_compatible?(artifact)

      _artifact_checksum_valid?(artifact)
    end

    def _artifact_runtime_compatible?(artifact)
      runtime_version = artifact["runtime_version"]
      return true if runtime_version.nil?

      runtime_version.to_s == Agent::VERSION
    end

    def _artifact_contract_compatible?(artifact)
      artifact.fetch("contract_fingerprint", "none") == _artifact_contract_fingerprint
    end

    def _artifact_checksum_valid?(artifact)
      code = artifact.fetch("code", "").to_s
      return false if code.strip.empty?

      checksum = artifact["code_checksum"].to_s
      checksum == _artifact_code_checksum(code)
    end

    def _artifact_degraded?(artifact)
      failures = artifact.fetch("failure_count", 0).to_i
      successes = artifact.fetch("success_count", 0).to_i
      failure_rate = artifact.fetch("recent_failure_rate", 0.0).to_f

      failures >= 3 && failure_rate > 0.6 && failures > successes
    end

    # --- Persisted Execution ---

    def _try_persisted_artifact_execution(name, args, kwargs, state)
      persisted_artifact = _select_persisted_artifact(name, state: state)
      return nil unless persisted_artifact

      _execute_or_repair_persisted_artifact(name, args, kwargs, persisted_artifact, state)
    end

    def _execute_or_repair_persisted_artifact(name, args, kwargs, persisted_artifact, state)
      persisted_outcome = _execute_persisted_artifact(name, args, kwargs, persisted_artifact, state)
      return persisted_outcome if persisted_outcome.ok?

      _handle_persisted_failure_outcome(
        name: name,
        args: args,
        kwargs: kwargs,
        persisted_artifact: persisted_artifact,
        state: state,
        outcome: persisted_outcome
      )
    rescue ExecutionError, WorkerCrashError, NonSerializableResultError, ToolRegistryViolationError,
           InvalidDependencyManifestError, DependencyManifestIncompatibleError,
           DependencyPolicyViolationError, DependencyResolutionError,
           DependencyInstallError, DependencyActivationError, ProviderError => e
      _handle_persisted_execution_exception(
        name: name,
        args: args,
        kwargs: kwargs,
        persisted_artifact: persisted_artifact,
        state: state,
        error: e
      )
    end

    def _handle_persisted_failure_outcome(name:, args:, kwargs:, persisted_artifact:, state:, outcome:)
      failure_class = _artifact_failure_class_for(outcome: outcome, error: nil)
      state.failure_class = failure_class
      return outcome if failure_class == "extrinsic"

      repaired_outcome = _repair_persisted_artifact(
        method_name: name,
        args: args,
        kwargs: kwargs,
        persisted_artifact: persisted_artifact,
        failure_class: failure_class,
        failure_message: outcome.error_message.to_s,
        state: state
      )
      return repaired_outcome if repaired_outcome&.ok?

      nil
    end

    def _handle_persisted_execution_exception(name:, args:, kwargs:, persisted_artifact:, state:, error:)
      failure_class = _artifact_failure_class_for(outcome: nil, error: error)
      state.failure_class = failure_class
      return _error_outcome_for(name, error) if failure_class == "extrinsic"

      repaired_outcome = _repair_persisted_artifact(
        method_name: name,
        args: args,
        kwargs: kwargs,
        persisted_artifact: persisted_artifact,
        failure_class: failure_class,
        failure_message: error.message.to_s,
        state: state
      )
      return repaired_outcome if repaired_outcome&.ok?

      warn "[AGENT ARTIFACT #{@role}.#{name}] persisted execution fallback: #{error.class}: #{error.message}" if @debug
      nil
    end

    def _execute_persisted_artifact(name, args, kwargs, artifact, state)
      _capture_persisted_artifact_state!(state, artifact)
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

    # --- Artifact Repair ---

    def _repair_persisted_artifact(
      method_name:,
      args:,
      kwargs:,
      persisted_artifact:,
      failure_class:,
      failure_message:,
      state:
    )
      return nil unless _artifact_repair_budget_available?(persisted_artifact)

      state.repair_attempted = true
      repair_user_prompt = _artifact_repair_user_prompt(
        method_name: method_name,
        args: args,
        kwargs: kwargs,
        persisted_artifact: persisted_artifact,
        failure_class: failure_class,
        failure_message: failure_message
      )
      repair_system_prompt = _build_system_prompt(call_context: _call_stack.last)

      repaired_program, state.generation_attempt = _generate_program_with_retry(
        method_name,
        repair_system_prompt,
        repair_user_prompt
      )
      _capture_generated_program_state!(
        state,
        repaired_program,
        method_name: method_name,
        args: args,
        kwargs: kwargs
      )
      _mark_repaired_program_state!(state, trigger: _repair_trigger_for(failure_class))
      environment_info = _prepare_dependency_environment!(
        method_name: method_name,
        normalized_dependencies: state.normalized_dependencies
      )
      _capture_environment_state!(state, environment_info)

      _execute_generated_program(
        method_name,
        state.code,
        args,
        kwargs,
        normalized_dependencies: state.normalized_dependencies,
        environment_info: environment_info,
        state: state
      )
    rescue ProviderError, ExecutionError, WorkerCrashError, NonSerializableResultError,
           InvalidDependencyManifestError, DependencyManifestIncompatibleError,
           DependencyPolicyViolationError, DependencyResolutionError,
           DependencyInstallError, DependencyActivationError => e
      warn "[AGENT REPAIR #{@role}.#{method_name}] repair attempt failed: #{e.class}: #{e.message}" if @debug
      nil
    end

    def _artifact_repair_budget_available?(artifact)
      repair_count = artifact.fetch("repair_count_since_regen", 0).to_i
      repair_count < Agent::MAX_REPAIRS_BEFORE_REGEN
    end

    def _repair_trigger_for(failure_class)
      case failure_class
      when "adaptive"
        "repair:adaptive_failure"
      when "intrinsic"
        "repair:intrinsic_failure"
      else
        "repair:unknown_failure"
      end
    end

    def _artifact_repair_user_prompt(method_name:, args:, kwargs:, persisted_artifact:, failure_class:, failure_message:)
      <<~PROMPT
        <repair_invocation>
        <method>#{method_name}</method>
        <args>#{args.inspect}</args>
        <kwargs>#{kwargs.inspect}</kwargs>
        <failure_class>#{failure_class}</failure_class>
        <failure_message>#{failure_message}</failure_message>
        <existing_code>
        #{persisted_artifact.fetch("code", "")}
        </existing_code>
        <artifact_metadata>
        <prompt_version>#{persisted_artifact["prompt_version"]}</prompt_version>
        <contract_fingerprint>#{persisted_artifact["contract_fingerprint"]}</contract_fingerprint>
        </artifact_metadata>
        </repair_invocation>

        <repair_goal>
        Repair this existing method implementation. Preserve intent and contract compatibility.
        Do not invent new capabilities. Ensure returned code executes for the provided args/kwargs.
        </repair_goal>

        <response_contract>
        - Return a GeneratedProgram payload with `code` and optional `dependencies`.
        - Set `result` to the raw domain value, or use `return` in generated code.
        </response_contract>
      PROMPT
    end

    # --- Artifact Metrics ---

    def _artifact_update_metrics!(artifact, state)
      if state.outcome&.ok?
        _artifact_increment_success!(artifact)
      else
        _artifact_increment_failure!(artifact, state)
      end
      _artifact_update_failure_rate!(artifact)
    end

    def _artifact_increment_success!(artifact)
      artifact["success_count"] = artifact["success_count"].to_i + 1
    end

    def _artifact_increment_failure!(artifact, state)
      artifact["failure_count"] = artifact["failure_count"].to_i + 1
      failure_class = _artifact_failure_class(state)
      _artifact_increment_failure_counter!(artifact, failure_class)
      artifact["last_failure_class"] = failure_class
      artifact["last_failure_reason"] = state.outcome&.error_message || state.error&.message || "unknown failure"
    end

    def _artifact_update_failure_rate!(artifact)
      successes = artifact["success_count"].to_i
      failures = artifact["failure_count"].to_i
      total = successes + failures
      artifact["recent_failure_rate"] = total.zero? ? 0.0 : (failures.to_f / total).round(4)
    end

    def _artifact_increment_failure_counter!(artifact, failure_class)
      key = case failure_class
            when "extrinsic"
              "extrinsic_failure_count"
            when "adaptive"
              "adaptive_failure_count"
            else
              "intrinsic_failure_count"
            end
      artifact[key] = artifact[key].to_i + 1
    end

    def _artifact_failure_class(state)
      _artifact_failure_class_for(outcome: state.outcome, error: state.error)
    end

    def _artifact_failure_class_for(outcome:, error:)
      failure_type = outcome&.error_type.to_s
      return "extrinsic" if EXTRINSIC_FAILURE_TYPES.include?(failure_type)
      return "adaptive" if ADAPTIVE_FAILURE_TYPES.include?(failure_type)
      return "intrinsic" unless failure_type.empty?

      return "extrinsic" if error.is_a?(TimeoutError) || error.is_a?(ProviderError)

      "intrinsic"
    end

    # --- Trigger Metadata ---

    def _artifact_trigger_failure_metadata(state)
      stage = state.latest_failure_stage.to_s
      return {} if stage.empty?

      metadata = {
        "trigger_stage" => stage,
        "trigger_error_class" => state.latest_failure_class.to_s,
        "trigger_error_message" => state.latest_failure_message.to_s
      }
      attempt_id = Array(state.attempt_failures).last&.fetch(:attempt_id, nil)
      metadata["trigger_attempt_id"] = attempt_id unless attempt_id.nil?
      metadata
    end
  end
end
