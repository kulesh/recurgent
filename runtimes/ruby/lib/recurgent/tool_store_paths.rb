# frozen_string_literal: true

require "digest"

class Agent
  # Agent::ToolStorePaths — filesystem paths for persisted tool registry and artifacts.
  module ToolStorePaths
    private

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
  end
end
