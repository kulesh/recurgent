# frozen_string_literal: true

class Agent
  TOOLSTORE_CONFIG_KEYS = %i[
    toolstore_root
    solver_shape_capture_enabled
    self_model_capture_enabled
    promotion_shadow_mode_enabled
    promotion_enforcement_enabled
    authority_enforcement_enabled
    authority_maintainers
  ].freeze

  def self.runtime_config
    @runtime_config ||= {
      gem_sources: DEFAULT_GEM_SOURCES.dup,
      source_mode: DEFAULT_SOURCE_MODE,
      allowed_gems: nil,
      blocked_gems: nil,
      toolstore_root: ENV.fetch("RECURGENT_TOOLSTORE_ROOT", Agent.default_toolstore_root),
      solver_shape_capture_enabled: _normalize_runtime_bool(
        ENV.fetch("RECURGENT_SOLVER_SHAPE_CAPTURE_ENABLED", "true")
      ),
      self_model_capture_enabled: _normalize_runtime_bool(
        ENV.fetch("RECURGENT_SELF_MODEL_CAPTURE_ENABLED", "true")
      ),
      promotion_shadow_mode_enabled: _normalize_runtime_bool(
        ENV.fetch("RECURGENT_PROMOTION_SHADOW_MODE_ENABLED", "true")
      ),
      promotion_enforcement_enabled: _normalize_runtime_bool(
        ENV.fetch("RECURGENT_PROMOTION_ENFORCEMENT_ENABLED", "false")
      ),
      authority_enforcement_enabled: _normalize_runtime_bool(
        ENV.fetch("RECURGENT_AUTHORITY_ENFORCEMENT_ENABLED", "true")
      ),
      authority_maintainers: _normalize_runtime_maintainers(
        ENV.fetch("RECURGENT_AUTHORITY_MAINTAINERS", ENV.fetch("USER", ""))
      )
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
    if options.key?(:solver_shape_capture_enabled)
      config[:solver_shape_capture_enabled] = _normalize_runtime_bool(options[:solver_shape_capture_enabled])
    end
    config[:self_model_capture_enabled] = _normalize_runtime_bool(options[:self_model_capture_enabled]) if options.key?(:self_model_capture_enabled)
    if options.key?(:promotion_shadow_mode_enabled)
      config[:promotion_shadow_mode_enabled] = _normalize_runtime_bool(options[:promotion_shadow_mode_enabled])
    end
    if options.key?(:promotion_enforcement_enabled)
      config[:promotion_enforcement_enabled] = _normalize_runtime_bool(options[:promotion_enforcement_enabled])
    end
    if options.key?(:authority_enforcement_enabled)
      config[:authority_enforcement_enabled] = _normalize_runtime_bool(options[:authority_enforcement_enabled])
    end
    return unless options.key?(:authority_maintainers)

    config[:authority_maintainers] = _normalize_runtime_maintainers(options[:authority_maintainers])
  end

  def self._normalize_runtime_maintainers(value)
    return [] if value.nil?

    raw = value.is_a?(String) ? value.split(",") : Array(value)
    raw.map { |entry| entry.to_s.strip.downcase }.reject(&:empty?).uniq
  end

  def self._normalize_runtime_bool(value)
    return value if [true, false].include?(value)

    normalized = value.to_s.strip.downcase
    return true if %w[1 true yes on].include?(normalized)
    return false if %w[0 false no off].include?(normalized)

    false
  end
end
