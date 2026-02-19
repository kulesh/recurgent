# frozen_string_literal: true

class Agent
  # Agent::ToolStore — JSON-backed persistence for delegated tool registry metadata.
  module ToolStore
    include ToolStoreIntentMetadata

    private

    def _hydrate_tool_registry!
      persisted_tools = _toolstore_load_registry_tools
      return if persisted_tools.empty?

      memory_tools = @context[:tools]
      @context[:tools] = if memory_tools.is_a?(Hash) && !memory_tools.empty?
                           persisted_tools.merge(memory_tools)
                         else
                           persisted_tools
                         end
    end

    def _persist_tool_registry_entry(role_name, metadata)
      tools = _toolstore_load_registry_tools
      role_key = role_name.to_s
      tools[role_key] = _toolstore_merged_registry_entry(tools[role_key], metadata)
      _toolstore_write_registry(tools)
    rescue StandardError => e
      warn "[AGENT TOOLSTORE #{@role}] failed to persist registry entry for #{role_name}: #{e.message}" if @debug
    end

    def _toolstore_touch_tool_usage(role_name, method_name:, outcome:, state: nil, artifact_checksum: nil)
      tools = _toolstore_load_registry_tools
      role_key = role_name.to_s
      metadata = tools[role_key]
      return unless metadata.is_a?(Hash)

      tools[role_key] = _toolstore_touched_registry_entry(
        metadata,
        method_name: method_name,
        outcome: outcome,
        state: state,
        artifact_checksum: artifact_checksum
      )
      _toolstore_write_registry(tools)
    rescue StandardError => e
      warn "[AGENT TOOLSTORE #{@role}] failed to update usage metrics for #{role_name}: #{e.message}" if @debug
    end

    def _toolstore_load_registry_tools
      path = _toolstore_registry_path
      return {} unless File.exist?(path)

      parsed = _toolstore_parse_registry(path)
      return {} unless _toolstore_schema_supported?(parsed["schema_version"])

      _toolstore_extract_registry_tools(parsed["tools"])
    rescue JSON::ParserError => e
      _toolstore_quarantine_corrupt_registry!(path, e)
      {}
    rescue StandardError => e
      warn "[AGENT TOOLSTORE #{@role}] failed to load registry: #{e.class}: #{e.message}" if @debug
      {}
    end

    def _toolstore_write_registry(tools)
      path = _toolstore_registry_path
      FileUtils.mkdir_p(File.dirname(path))
      payload = {
        schema_version: Agent::TOOLSTORE_SCHEMA_VERSION,
        tools: _json_safe(tools)
      }

      temp_path = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.write(temp_path, JSON.generate(payload))
      File.rename(temp_path, path)
    ensure
      File.delete(temp_path) if defined?(temp_path) && temp_path && File.exist?(temp_path)
    end

    def _toolstore_quarantine_corrupt_registry!(path, error)
      return unless File.exist?(path)

      quarantined_path = "#{path}.corrupt-#{Time.now.utc.strftime("%Y%m%dT%H%M%S")}"
      FileUtils.mv(path, quarantined_path)
      if @debug
        warn(
          "[AGENT TOOLSTORE #{@role}] quarantined corrupt registry: #{File.basename(quarantined_path)} (#{error.class})"
        )
      end
    rescue StandardError => e
      warn "[AGENT TOOLSTORE #{@role}] failed to quarantine corrupt registry: #{e.message}" if @debug
    end

    def _normalize_loaded_tool_metadata(metadata)
      case metadata
      when Hash
        metadata.each_with_object({}) do |(key, value), normalized|
          normalized[_toolstore_metadata_key(key)] = _normalize_loaded_tool_metadata(value)
        end
      when Array
        metadata.map { |entry| _normalize_loaded_tool_metadata(entry) }
      else
        metadata
      end
    end

    def _toolstore_metadata_key(key)
      return key.to_sym if key.is_a?(String)

      key
    end

    def _toolstore_timestamp
      Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
    end

    def _toolstore_merged_registry_entry(existing, metadata)
      normalized_existing = existing.is_a?(Hash) ? existing : {}
      normalized = _normalize_loaded_tool_metadata(metadata)
      timestamp = _toolstore_timestamp

      merged = normalized_existing.merge(normalized)
      merged[:methods] = _toolstore_merged_method_names(normalized_existing, normalized)
      merged[:aliases] = _toolstore_merged_aliases(normalized_existing, normalized)
      _toolstore_apply_intent_metadata!(merged, normalized_existing, normalized)
      merged[:created_at] ||= timestamp
      merged[:last_used_at] = timestamp
      merged[:usage_count] = normalized_existing.fetch(:usage_count, 0).to_i + 1
      merged[:success_count] = normalized_existing.fetch(:success_count, 0).to_i
      merged[:failure_count] = normalized_existing.fetch(:failure_count, 0).to_i
      merged
    end

    def _toolstore_touched_registry_entry(metadata, method_name:, outcome:, state:, artifact_checksum:)
      updated = metadata.dup
      updated[:last_used_at] = _toolstore_timestamp
      updated[:usage_count] = metadata.fetch(:usage_count, 0).to_i + 1
      _toolstore_apply_outcome_counters!(updated, outcome)
      _toolstore_capture_method_name!(updated, method_name) if outcome&.ok?
      _toolstore_update_method_state_keys!(updated, method_name: method_name, state: state)
      _toolstore_update_state_key_consistency_ratio!(updated)
      _toolstore_update_namespace_pressure!(updated, method_name: method_name, state: state)
      _toolstore_update_version_scorecard!(
        updated,
        method_name: method_name,
        artifact_checksum: artifact_checksum,
        outcome: outcome,
        state: state
      )
      _toolstore_update_lifecycle_snapshot!(updated, state: state)
      updated
    end

    def _toolstore_apply_outcome_counters!(metadata, outcome)
      if outcome&.ok?
        metadata[:success_count] = metadata.fetch(:success_count, 0).to_i + 1
      else
        metadata[:failure_count] = metadata.fetch(:failure_count, 0).to_i + 1
      end
    end

    def _toolstore_capture_method_name!(metadata, method_name)
      method = method_name.to_s.strip
      return if method.empty?

      methods = _toolstore_method_names(metadata)
      return if methods.include?(method)

      metadata[:methods] = methods.append(method)
    end

    def _toolstore_merged_method_names(existing, incoming)
      (_toolstore_method_names(existing) + _toolstore_method_names(incoming)).uniq
    end

    def _toolstore_merged_aliases(existing, incoming)
      (_toolstore_aliases(existing) + _toolstore_aliases(incoming)).uniq
    end

    def _toolstore_method_names(metadata)
      return [] unless metadata.is_a?(Hash)

      Array(metadata[:methods] || metadata["methods"]).map { |name| name.to_s.strip }.reject(&:empty?).uniq
    end

    def _toolstore_aliases(metadata)
      return [] unless metadata.is_a?(Hash)

      Array(metadata[:aliases] || metadata["aliases"]).map { |name| name.to_s.strip }.reject(&:empty?).uniq
    end

    def _toolstore_parse_registry(path)
      JSON.parse(File.read(path))
    end

    def _toolstore_update_method_state_keys!(metadata, method_name:, state:)
      return unless state

      keys = _toolstore_state_keys_from_code(state.code.to_s)
      return if keys.empty?

      method_profiles = _toolstore_method_state_key_profiles(metadata)
      method_profiles[method_name.to_s] = keys
      metadata[:method_state_keys] = method_profiles
    end

    def _toolstore_update_state_key_consistency_ratio!(metadata)
      profiles = _toolstore_method_state_key_profiles(metadata)
      return metadata[:state_key_consistency_ratio] = 1.0 if profiles.empty?

      primary_keys = profiles.values.filter_map { |keys| Array(keys).map(&:to_s).sort.first }
      return metadata[:state_key_consistency_ratio] = 1.0 if primary_keys.empty?

      metadata[:state_key_consistency_ratio] = primary_keys.tally.values.max.to_f.fdiv(primary_keys.length).round(4)
    end

    def _toolstore_update_namespace_pressure!(metadata, method_name:, state:)
      profiles = _toolstore_method_state_key_profiles(metadata)
      primary_keys = profiles.values.filter_map { |keys| Array(keys).map(&:to_s).sort.first }
      metadata[:namespace_key_collision_count] = _toolstore_namespace_key_collision_count(primary_keys)

      lifetime_profiles = _toolstore_merge_state_key_lifetimes(metadata, state)
      metadata[:state_key_lifetimes] = lifetime_profiles
      metadata[:namespace_multi_lifetime_key_count] =
        lifetime_profiles.values.count { |lifetimes| Array(lifetimes).uniq.length > 1 }

      metadata[:namespace_continuity_violation_count] =
        metadata.fetch(:namespace_continuity_violation_count, 0).to_i +
        (_toolstore_namespace_continuity_violation?(profiles: profiles, method_name: method_name, state: state) ? 1 : 0)

      return unless state

      state.namespace_key_collision_count = metadata[:namespace_key_collision_count].to_i
      state.namespace_multi_lifetime_key_count = metadata[:namespace_multi_lifetime_key_count].to_i
      state.namespace_continuity_violation_count = metadata[:namespace_continuity_violation_count].to_i
    end

    def _toolstore_namespace_key_collision_count(primary_keys)
      normalized = Array(primary_keys).map(&:to_s).reject(&:empty?)
      return 0 if normalized.length <= 1

      normalized.combination(2).count { |left, right| left != right }
    end

    def _toolstore_merge_state_key_lifetimes(metadata, state)
      existing = _toolstore_state_key_lifetimes(metadata)
      observed = _toolstore_state_key_lifetimes_from_code(state&.code.to_s)
      observed.each do |key, lifetimes|
        merged = (Array(existing[key]) + Array(lifetimes)).map(&:to_s).reject(&:empty?).uniq.sort
        existing[key] = merged
      end
      existing
    end

    def _toolstore_state_key_lifetimes(metadata)
      raw = metadata[:state_key_lifetimes] || metadata["state_key_lifetimes"]
      return {} unless raw.is_a?(Hash)

      raw.each_with_object({}) do |(key, lifetimes), normalized|
        normalized[key.to_s] = Array(lifetimes).map(&:to_s).reject(&:empty?).uniq.sort
      end
    end

    def _toolstore_state_key_lifetimes_from_code(code)
      _toolstore_state_keys_from_code(code).each_with_object({}) do |key, profiles|
        key_pattern = Regexp.escape(key)
        lifetimes = []
        lifetimes << "durable" if %w[tools patterns role_profile proposals].include?(key)
        if code.match?(/context\[(?::|["'])#{key_pattern}["']?\]\s*(?:<<|\.push\(|\.append\()/)
          lifetimes << "session"
        end
        if code.match?(/context\[(?::|["'])#{key_pattern}["']?\]\s*=.*context\.fetch\((?::|["'])#{key_pattern}/m) ||
           code.match?(/context\[(?::|["'])#{key_pattern}["']?\]\s*[+\-*\/%]=/m)
          lifetimes << "role"
        end
        if key.match?(/\A(?:tmp|temp|scratch|attempt|working)_?/)
          lifetimes << "attempt"
        end
        lifetimes << "role" if lifetimes.empty?
        profiles[key] = lifetimes.uniq.sort
      end
    end

    def _toolstore_namespace_continuity_violation?(profiles:, method_name:, state:)
      primary_keys = profiles.values.filter_map { |keys| Array(keys).map(&:to_s).sort.first }
      return true if state&.guardrail_violation_subtype.to_s.include?("continuity")
      return false if primary_keys.uniq.length <= 1

      dominant_key = primary_keys.tally.max_by { |_key, count| count }&.first
      return false if dominant_key.to_s.empty?

      method_keys = Array(profiles[method_name.to_s]).map(&:to_s).reject(&:empty?).sort
      return false if method_keys.empty?

      method_keys.first != dominant_key
    end

    def _toolstore_update_version_scorecard!(metadata, method_name:, artifact_checksum:, outcome:, state:)
      checksum = artifact_checksum.to_s
      return if checksum.empty?

      scorecards = metadata[:version_scorecards]
      scorecards = metadata[:version_scorecards] = {} unless scorecards.is_a?(Hash)
      key = "#{method_name}@#{checksum}"
      scorecard = scorecards[key] || scorecards[key.to_sym]
      unless scorecard.is_a?(Hash)
        scorecard = scorecards[key] = {
          calls: 0,
          successes: 0,
          failures: 0,
          contract_pass_count: 0,
          contract_fail_count: 0,
          guardrail_retry_exhausted_count: 0,
          outcome_retry_exhausted_count: 0,
          wrong_boundary_count: 0,
          provenance_violation_count: 0,
          sessions: [],
          state_key_consistency_ratio: 1.0,
          state_key_entropy: nil,
          sibling_method_state_agreement: nil,
          updated_at: nil
        }
      end
      scorecards.delete(key.to_sym)
      scorecards[key] = scorecard

      scorecard[:calls] = scorecard.fetch(:calls, 0).to_i + 1
      if outcome&.ok?
        scorecard[:successes] = scorecard.fetch(:successes, 0).to_i + 1
      else
        scorecard[:failures] = scorecard.fetch(:failures, 0).to_i + 1
      end
      if state&.contract_validation_applied == true && state.contract_validation_passed == true
        scorecard[:contract_pass_count] = scorecard.fetch(:contract_pass_count, 0).to_i + 1
      elsif state&.contract_validation_applied == true && state.contract_validation_passed == false
        scorecard[:contract_fail_count] = scorecard.fetch(:contract_fail_count, 0).to_i + 1
      end
      if state&.guardrail_retry_exhausted == true
        scorecard[:guardrail_retry_exhausted_count] = scorecard.fetch(:guardrail_retry_exhausted_count, 0).to_i + 1
      end
      if state&.outcome_repair_retry_exhausted == true
        scorecard[:outcome_retry_exhausted_count] = scorecard.fetch(:outcome_retry_exhausted_count, 0).to_i + 1
      end
      if outcome&.error_type.to_s == "wrong_tool_boundary"
        scorecard[:wrong_boundary_count] = scorecard.fetch(:wrong_boundary_count, 0).to_i + 1
      end
      if outcome&.error_type.to_s == "tool_registry_violation" && outcome&.error_message.to_s.match?(/provenance/i)
        scorecard[:provenance_violation_count] = scorecard.fetch(:provenance_violation_count, 0).to_i + 1
      end

      sessions = Array(scorecard[:sessions])
      trace_id = @trace_id.to_s
      sessions << trace_id unless trace_id.empty? || sessions.include?(trace_id)
      scorecard[:sessions] = sessions.last(200)
      scorecard[:state_key_consistency_ratio] = metadata[:state_key_consistency_ratio] || 1.0
      scorecard[:lifecycle_state] = state&.lifecycle_state if state&.lifecycle_state
      scorecard[:policy_version] = state&.promotion_policy_version if state&.promotion_policy_version
      scorecard[:last_decision] = state&.lifecycle_decision if state&.lifecycle_decision
      scorecard[:updated_at] = _toolstore_timestamp
    end

    def _toolstore_update_lifecycle_snapshot!(metadata, state:)
      return unless state

      metadata[:promotion_policy_version] = state.promotion_policy_version if state.promotion_policy_version
      metadata[:lifecycle_state] = state.lifecycle_state if state.lifecycle_state
      metadata[:lifecycle_decision] = state.lifecycle_decision if state.lifecycle_decision
    end

    def _toolstore_method_state_key_profiles(metadata)
      raw = metadata[:method_state_keys] || metadata["method_state_keys"]
      return {} unless raw.is_a?(Hash)

      raw.each_with_object({}) do |(method_name, keys), normalized|
        normalized[method_name.to_s] = Array(keys).map(&:to_s).reject(&:empty?).uniq
      end
    end

    def _toolstore_state_keys_from_code(code)
      code.scan(/context\[(?::|["'])([a-zA-Z0-9_]+)["']?\]/).flatten.uniq
    end

    def _toolstore_schema_supported?(schema_version)
      return true if schema_version.nil?
      return true if schema_version.to_i == Agent::TOOLSTORE_SCHEMA_VERSION

      warn "[AGENT TOOLSTORE #{@role}] ignored registry schema=#{schema_version}" if @debug
      false
    end

    def _toolstore_extract_registry_tools(raw_tools)
      return {} unless raw_tools.is_a?(Hash)

      raw_tools.each_with_object({}) do |(name, metadata), normalized|
        normalized[name.to_s] = _normalize_loaded_tool_metadata(metadata)
      end
    end
  end
end
