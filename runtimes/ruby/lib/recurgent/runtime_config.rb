# frozen_string_literal: true

class Agent
  TOOLSTORE_CONFIG_KEYS = %i[toolstore_root].freeze

  def self.runtime_config
    @runtime_config ||= {
      gem_sources: DEFAULT_GEM_SOURCES.dup,
      source_mode: DEFAULT_SOURCE_MODE,
      allowed_gems: nil,
      blocked_gems: nil,
      toolstore_root: ENV.fetch("RECURGENT_TOOLSTORE_ROOT", Agent.default_toolstore_root)
    }
  end

  def self.configure_runtime(gem_sources: nil, source_mode: nil, allowed_gems: nil, blocked_gems: nil, **options)
    config = runtime_config.dup
    config[:gem_sources] = _normalize_runtime_sources(gem_sources) unless gem_sources.nil?
    config[:source_mode] = source_mode.to_s unless source_mode.nil?
    config[:allowed_gems] = _normalize_runtime_gem_list(allowed_gems)
    config[:blocked_gems] = _normalize_runtime_gem_list(blocked_gems)

    _apply_toolstore_runtime_options!(config, options)
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

  def self._apply_toolstore_runtime_options!(config, options)
    unknown_options = options.keys - TOOLSTORE_CONFIG_KEYS
    raise ArgumentError, "Unknown runtime config options: #{unknown_options.join(", ")}" unless unknown_options.empty?

    config[:toolstore_root] = options[:toolstore_root].to_s if options.key?(:toolstore_root)
  end
end
