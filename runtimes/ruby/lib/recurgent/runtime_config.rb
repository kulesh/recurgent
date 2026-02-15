# frozen_string_literal: true

class Agent
  TOOLSTORE_CONFIG_KEYS = %i[
    toolstore_enabled
    toolstore_artifact_read_enabled
    toolstore_repair_enabled
    toolstore_pruning_enabled
    toolstore_root
  ].freeze

  def self.runtime_config
    @runtime_config ||= {
      gem_sources: DEFAULT_GEM_SOURCES.dup,
      source_mode: DEFAULT_SOURCE_MODE,
      allowed_gems: nil,
      blocked_gems: nil,
      toolstore_enabled: _env_bool("RECURGENT_TOOLSTORE_ENABLED", default: false),
      toolstore_artifact_read_enabled: _env_bool("RECURGENT_TOOLSTORE_ARTIFACT_READ_ENABLED", default: false),
      toolstore_repair_enabled: _env_bool("RECURGENT_TOOLSTORE_REPAIR_ENABLED", default: false),
      toolstore_pruning_enabled: _env_bool("RECURGENT_TOOLSTORE_PRUNING_ENABLED", default: false),
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

  def self._env_bool(name, default:)
    raw = ENV.fetch(name, nil)
    return default if raw.nil?

    %w[1 true yes on].include?(raw.to_s.strip.downcase)
  end

  def self._apply_toolstore_runtime_options!(config, options)
    unknown_options = options.keys - TOOLSTORE_CONFIG_KEYS
    raise ArgumentError, "Unknown runtime config options: #{unknown_options.join(", ")}" unless unknown_options.empty?

    _apply_toolstore_bool_option!(config, options, :toolstore_enabled)
    _apply_toolstore_bool_option!(config, options, :toolstore_artifact_read_enabled)
    _apply_toolstore_bool_option!(config, options, :toolstore_repair_enabled)
    _apply_toolstore_bool_option!(config, options, :toolstore_pruning_enabled)
    config[:toolstore_root] = options[:toolstore_root].to_s if options.key?(:toolstore_root)
  end

  def self._apply_toolstore_bool_option!(config, options, key)
    return unless options.key?(key)

    config[key] = options[key] ? true : false
  end
end
