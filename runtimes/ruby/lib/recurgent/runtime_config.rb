# frozen_string_literal: true

class Agent
  def self.runtime_config
    @runtime_config ||= {
      gem_sources: DEFAULT_GEM_SOURCES.dup,
      source_mode: DEFAULT_SOURCE_MODE,
      allowed_gems: nil,
      blocked_gems: nil
    }
  end

  def self.configure_runtime(gem_sources: nil, source_mode: nil, allowed_gems: nil, blocked_gems: nil)
    config = runtime_config.dup
    config[:gem_sources] = _normalize_runtime_sources(gem_sources) if gem_sources
    config[:source_mode] = source_mode.to_s if source_mode
    config[:allowed_gems] = _normalize_runtime_gem_list(allowed_gems)
    config[:blocked_gems] = _normalize_runtime_gem_list(blocked_gems)
    @runtime_config = config
  end

  def self.reset_runtime_config!
    @runtime_config = nil
  end

  def self._normalize_runtime_sources(sources)
    return DEFAULT_GEM_SOURCES.dup if sources.nil?

    normalized = Array(sources).map { |source| source.to_s.strip }.reject(&:empty?).uniq
    return DEFAULT_GEM_SOURCES.dup if normalized.empty?

    normalized
  end

  def self._normalize_runtime_gem_list(value)
    return nil if value.nil?

    Array(value).map { |name| name.to_s.strip.downcase }.reject(&:empty?).uniq
  end
end
