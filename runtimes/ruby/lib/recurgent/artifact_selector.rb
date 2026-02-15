# frozen_string_literal: true

class Agent
  # Agent::ArtifactSelector — persisted artifact compatibility and selection policy.
  module ArtifactSelector
    private

    def _select_persisted_artifact(method_name, state:)
      return nil unless _toolstore_enabled? && _toolstore_artifact_read_enabled?

      artifact = _artifact_load(method_name)
      return nil unless artifact
      return nil unless _artifact_compatible_for_execution?(artifact)
      return nil if _artifact_degraded?(artifact)

      state.artifact_prompt_version = artifact["prompt_version"]
      state.artifact_contract_fingerprint = artifact["contract_fingerprint"]
      artifact
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
  end
end
