# frozen_string_literal: true

class Agent
  # Agent::PersistedExecution — persisted artifact execution/repair routing before generation.
  module PersistedExecution
    private

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
    rescue ExecutionError, WorkerCrashError, NonSerializableResultError,
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
  end
end
