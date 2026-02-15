# frozen_string_literal: true

class Agent
  # Agent::ArtifactRepair — persisted artifact repair flow with bounded retry budget.
  module ArtifactRepair
    private

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
  end
end
