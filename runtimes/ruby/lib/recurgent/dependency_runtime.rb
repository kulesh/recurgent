# frozen_string_literal: true

class Agent
  private

  def _prepare_dependency_environment!(method_name:, normalized_dependencies:)
    _ = method_name
    manifest = _resolve_call_manifest(normalized_dependencies)
    return _empty_environment_info if manifest.empty?

    _enforce_dependency_policy!(manifest)
    env_info = _environment_manager.ensure_environment!(manifest)
    _activate_environment!(env_info[:env_dir])
    @env_id = env_info[:env_id]
    env_info
  end

  def _resolve_call_manifest(normalized_dependencies)
    incoming_manifest = normalized_dependencies || []
    return _initialize_manifest!(incoming_manifest) if @env_manifest.nil?
    return @env_manifest if incoming_manifest.empty?

    _ensure_additive_manifest!(@env_manifest, incoming_manifest)
    @env_manifest = incoming_manifest
  end

  def _initialize_manifest!(manifest)
    @env_manifest = manifest
  end

  def _ensure_additive_manifest!(current_manifest, incoming_manifest)
    return if _manifest_additive?(current_manifest, incoming_manifest)

    raise DependencyManifestIncompatibleError,
          "dependencies for #{@role} are incompatible with prior manifest (existing gems must remain with identical versions)"
  end

  def _manifest_additive?(current_manifest, incoming_manifest)
    incoming_versions = incoming_manifest.each_with_object({}) do |dependency, versions|
      versions[dependency[:name]] = dependency[:version]
    end

    current_manifest.all? do |dependency|
      incoming_versions[dependency[:name]] == dependency[:version]
    end
  end

  def _enforce_dependency_policy!(manifest)
    _validate_source_policy!
    manifest.each { |dependency| _validate_dependency_policy!(dependency[:name]) }
  end

  def _validate_source_policy!
    return unless @runtime_config[:source_mode].to_s == "internal_only"

    sources = @runtime_config[:gem_sources]
    raise DependencyPolicyViolationError, "source_mode internal_only requires at least one internal gem source" if sources.empty?
    return unless sources.any? { |source| source.include?("rubygems.org") }

    raise DependencyPolicyViolationError, "source_mode internal_only forbids public source https://rubygems.org"
  end

  def _validate_dependency_policy!(name)
    allowed = @runtime_config[:allowed_gems]
    blocked = @runtime_config[:blocked_gems]

    raise DependencyPolicyViolationError, "dependency policy violation for #{name}: not in allowed_gems" if allowed && !allowed.include?(name)
    return unless blocked&.include?(name)

    raise DependencyPolicyViolationError, "dependency policy violation for #{name}: blocked by blocked_gems"
  end

  def _environment_manager
    @environment_manager ||= EnvironmentManager.new(
      gem_sources: @runtime_config[:gem_sources],
      source_mode: @runtime_config[:source_mode]
    )
  end

  def _activate_environment!(env_dir)
    return unless env_dir

    ENV["BUNDLE_GEMFILE"] = File.join(env_dir, "Gemfile")
    ENV["BUNDLE_PATH"] = File.join(env_dir, "vendor", "bundle")
    require "bundler/setup"
  rescue StandardError => e
    raise DependencyActivationError, "Dependency activation failed for #{@role}: #{e.message}"
  end

  def _empty_environment_info
    {
      env_id: @env_id,
      environment_cache_hit: nil,
      env_prepare_ms: nil,
      env_resolve_ms: nil,
      env_install_ms: nil,
      env_dir: nil
    }
  end
end
