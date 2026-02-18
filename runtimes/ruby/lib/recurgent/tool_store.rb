# frozen_string_literal: true

require "digest"

class Agent
  # Agent::ToolStore — JSON-backed persistence for delegated tool registry metadata.
  #
  # Consolidates filesystem paths, intent-signature merge helpers, and
  # registry integrity guardrails into a single module.
  module ToolStore
    private

    # -- Filesystem paths ------------------------------------------------------

    def _toolstore_root
      root = @runtime_config[:toolstore_root]
      root = Agent.default_toolstore_root if root.nil? || root.to_s.strip.empty?
      root.to_s
    end

    def _toolstore_registry_path
      File.join(_toolstore_root, "registry.json")
    end

    def _toolstore_patterns_path
      File.join(_toolstore_root, "patterns.json")
    end

    def _toolstore_artifacts_root
      File.join(_toolstore_root, "artifacts")
    end

    def _toolstore_artifact_path(role_name:, method_name:)
      role_segment = _toolstore_safe_segment(role_name)
      method_segment = _toolstore_safe_segment(method_name)
      File.join(_toolstore_artifacts_root, role_segment, "#{method_segment}.json")
    end

    def _toolstore_safe_segment(value)
      raw = value.to_s
      normalized = raw.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      normalized = "item" if normalized.empty?
      digest = Digest::SHA256.hexdigest(raw)[0, 8]
      "#{normalized[0, 48]}-#{digest}"
    end

    # -- Intent-signature merge helpers ----------------------------------------

    def _toolstore_apply_intent_metadata!(merged, existing, incoming)
      signatures = (_toolstore_intent_signatures(existing) + _toolstore_intent_signatures(incoming)).uniq.last(6)
      merged[:intent_signatures] = signatures
      merged[:intent_signature] = signatures.last unless signatures.empty?
    end

    def _toolstore_intent_signatures(metadata)
      return [] unless metadata.is_a?(Hash)

      signatures = Array(metadata[:intent_signatures] || metadata["intent_signatures"])
      signatures << metadata[:intent_signature] if metadata.key?(:intent_signature)
      signatures << metadata["intent_signature"] if metadata.key?("intent_signature")
      signatures.map { |value| value.to_s.strip }.reject(&:empty?).uniq
    end

    # -- Registry integrity guardrails -----------------------------------------

    def _enforce_tool_registry_integrity!(method_name:, phase:)
      registry = @context[:tools]
      return if registry.nil?
      raise ToolRegistryViolationError, "context[:tools] must be a Hash" unless registry.is_a?(Hash)

      executable_paths = _tool_registry_executable_paths(registry, path: "context[:tools]")
      return if executable_paths.empty?

      raise ToolRegistryViolationError,
            "Tool registry metadata cannot store executable objects " \
            "(#{phase} #{@role}.#{method_name}): #{executable_paths.join(", ")}"
    end

    def _tool_registry_executable_paths(value, path:)
      return [path] if _tool_registry_executable_value?(value)
      return _tool_registry_array_executable_paths(value, path: path) if value.is_a?(Array)
      return _tool_registry_hash_executable_paths(value, path: path) if value.is_a?(Hash)

      []
    end

    def _tool_registry_array_executable_paths(array, path:)
      array.each_with_index.flat_map do |entry, index|
        _tool_registry_executable_paths(entry, path: "#{path}[#{index}]")
      end
    end

    def _tool_registry_hash_executable_paths(hash, path:)
      hash.flat_map do |key, entry|
        child_path = "#{path}[#{key.inspect}]"
        _tool_registry_executable_paths(entry, path: child_path)
      end
    end

    def _tool_registry_executable_value?(value)
      return true if _tool_registry_explicit_executable_type?(value)
      return false if _tool_registry_plain_metadata_value?(value)

      value.respond_to?(:call)
    end

    def _tool_registry_explicit_executable_type?(value)
      value.is_a?(Proc) || value.is_a?(Method) || value.is_a?(UnboundMethod) || value.is_a?(Agent)
    end

    def _tool_registry_plain_metadata_value?(value)
      case value
      when nil, String, Numeric, Symbol, TrueClass, FalseClass
        true
      else
        false
      end
    end

    # -- Hydration and persistence ---------------------------------------------

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

    def _toolstore_touch_tool_usage(role_name, method_name:, outcome:)
      tools = _toolstore_load_registry_tools
      role_key = role_name.to_s
      metadata = tools[role_key]
      return unless metadata.is_a?(Hash)

      tools[role_key] = _toolstore_touched_registry_entry(metadata, method_name: method_name, outcome: outcome)
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

    # -- Metadata normalization ------------------------------------------------

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

    # -- Registry entry merging ------------------------------------------------

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

    def _toolstore_touched_registry_entry(metadata, method_name:, outcome:)
      updated = metadata.dup
      updated[:last_used_at] = _toolstore_timestamp
      updated[:usage_count] = metadata.fetch(:usage_count, 0).to_i + 1
      _toolstore_apply_outcome_counters!(updated, outcome)
      _toolstore_capture_method_name!(updated, method_name) if outcome&.ok?
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
