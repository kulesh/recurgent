# frozen_string_literal: true

require "digest"

class Agent
  # Agent::ArtifactStore — persisted generated-program artifacts and call fitness metrics.
  module ArtifactStore
    include ArtifactTriggerMetadata

    private

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
      legacy_mode = !previous_checksum.nil? && !artifact.key?("lifecycle")
      _artifact_evaluate_promotion_shadow!(artifact, state: state, timestamp: timestamp, legacy_mode: legacy_mode)

      artifact["last_used_at"] = timestamp
      artifact["last_duration_ms"] = duration_ms.round(1)
      _artifact_write(method_name, artifact)
      _toolstore_touch_tool_usage(
        @role,
        method_name: method_name,
        outcome: state.outcome,
        state: state,
        artifact_checksum: new_checksum
      )
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
        "versions" => {},
        "dependencies" => [],
        "success_count" => 0,
        "failure_count" => 0,
        "intrinsic_failure_count" => 0,
        "adaptive_failure_count" => 0,
        "extrinsic_failure_count" => 0,
        "recent_failure_rate" => 0.0,
        "scorecards" => {},
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

    def _artifact_scorecards(method_name)
      artifact = _artifact_load(method_name)
      return {} unless artifact.is_a?(Hash)

      scorecards = artifact["scorecards"]
      scorecards.is_a?(Hash) ? scorecards : {}
    end

    def _artifact_scorecard_for(artifact, artifact_checksum: nil)
      return nil unless artifact.is_a?(Hash)

      scorecards = artifact["scorecards"]
      return nil unless scorecards.is_a?(Hash)

      checksum = artifact_checksum.to_s
      checksum = artifact["code_checksum"].to_s if checksum.empty?
      candidate = scorecards[checksum]
      candidate.is_a?(Hash) ? candidate : nil
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
      _artifact_update_version_payload!(
        artifact,
        checksum: checksum,
        code: code,
        dependencies: artifact["dependencies"],
        timestamp: timestamp
      )
      artifact["created_at"] ||= timestamp
    end

    def _artifact_update_version_payload!(artifact, checksum:, code:, dependencies:, timestamp:)
      versions = artifact["versions"]
      versions = artifact["versions"] = {} unless versions.is_a?(Hash)

      existing = versions[checksum]
      created_at = existing.is_a?(Hash) ? existing["created_at"] : timestamp
      versions[checksum] = {
        "code" => code,
        "dependencies" => dependencies || [],
        "created_at" => created_at,
        "last_used_at" => timestamp
      }

      # Keep recent versions bounded to avoid unbounded artifact growth.
      if versions.length > 8
        sorted = versions.sort_by { |_, payload| payload.is_a?(Hash) ? payload["last_used_at"].to_s : "" }
        keep = sorted.last(8).to_h
        artifact["versions"] = keep
      end
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
  end
end
