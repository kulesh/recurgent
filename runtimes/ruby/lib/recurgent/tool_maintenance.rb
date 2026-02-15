# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require "time"

class Agent
  # Agent::ToolMaintenance — stale-tool inspection and prune/archive operations for persisted registry.
  class ToolMaintenance
    def initialize(toolstore_root: Agent.default_toolstore_root)
      @toolstore_root = toolstore_root.to_s
    end

    def list_stale_tools(stale_days: 30, limit: nil)
      tools = _load_registry.fetch("tools", {})
      stale_cutoff = _stale_cutoff(stale_days)
      stale = tools.filter_map { |name, metadata| _stale_tool_entry(name, metadata, stale_cutoff) }
      sorted = stale.sort_by { |entry| entry["last_used_at"] || "" }
      return sorted if limit.nil?

      sorted.first(limit.to_i)
    end

    def prune_stale_tools(stale_days: 30, dry_run: true, mode: "archive")
      registry = _load_registry
      tools = registry.fetch("tools", {})
      stale = list_stale_tools(stale_days: stale_days)
      stale_names = stale.map { |entry| entry["name"] }
      return _prune_summary(mode: mode, dry_run: dry_run, stale: stale, pruned: 0) if stale_names.empty?

      unless dry_run
        case mode
        when "archive"
          _archive_tools!(registry, stale_names)
        when "delete"
          stale_names.each { |name| tools.delete(name) }
        else
          raise ArgumentError, "Unsupported prune mode: #{mode.inspect}"
        end
        _write_registry(registry)
      end

      _prune_summary(mode: mode, dry_run: dry_run, stale: stale, pruned: stale_names.length)
    end

    private

    def _prune_summary(mode:, dry_run:, stale:, pruned:)
      {
        "mode" => mode,
        "dry_run" => dry_run,
        "stale_count" => stale.length,
        "pruned_count" => pruned,
        "stale_tools" => stale
      }
    end

    def _archive_tools!(registry, stale_names)
      registry["archived_tools"] ||= {}
      tools = registry.fetch("tools", {})
      archived = registry["archived_tools"]
      timestamp = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")

      stale_names.each do |name|
        metadata = tools.delete(name)
        next unless metadata.is_a?(Hash)

        archived[name] = metadata.merge("archived_at" => timestamp)
      end
    end

    def _stale_cutoff(stale_days)
      Time.now.utc - (stale_days.to_i * 86_400)
    end

    def _stale_tool_entry(name, metadata, stale_cutoff)
      last_used = _parse_timestamp(metadata["last_used_at"])
      return nil unless last_used.nil? || last_used < stale_cutoff

      success_count = metadata.fetch("success_count", 0).to_i
      failure_count = metadata.fetch("failure_count", 0).to_i
      total = success_count + failure_count
      success_rate = total.zero? ? nil : (success_count.to_f / total).round(4)
      {
        "name" => name,
        "purpose" => metadata["purpose"],
        "usage_count" => metadata.fetch("usage_count", 0).to_i,
        "last_used_at" => metadata["last_used_at"],
        "created_at" => metadata["created_at"],
        "success_rate" => success_rate
      }
    end

    def _registry_path
      File.join(@toolstore_root, "registry.json")
    end

    def _load_registry
      path = _registry_path
      return _empty_registry unless File.exist?(path)

      parsed = JSON.parse(File.read(path))
      parsed["tools"] ||= {}
      parsed
    rescue JSON::ParserError
      _empty_registry
    end

    def _write_registry(registry)
      path = _registry_path
      FileUtils.mkdir_p(File.dirname(path))
      temp_path = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.write(temp_path, JSON.generate(registry))
      File.rename(temp_path, path)
    ensure
      File.delete(temp_path) if defined?(temp_path) && temp_path && File.exist?(temp_path)
    end

    def _empty_registry
      {
        "schema_version" => Agent::TOOLSTORE_SCHEMA_VERSION,
        "tools" => {}
      }
    end

    def _parse_timestamp(value)
      return nil if value.nil? || value.to_s.strip.empty?

      Time.parse(value.to_s).utc
    rescue ArgumentError
      nil
    end
  end
end
