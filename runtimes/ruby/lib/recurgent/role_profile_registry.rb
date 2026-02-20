# frozen_string_literal: true

class Agent
  # Agent::RoleProfileRegistry — active role-profile binding, versioning, and persistence.
  module RoleProfileRegistry
    private

    def _hydrate_role_profiles!
      payload = _role_profile_registry_role_payload(@role)
      return if payload.empty?

      profiles = _role_profile_registry_normalize_versions(payload["versions"] || payload[:versions], role: @role)
      return if profiles.empty?

      preferred = payload["active_version"] || payload[:active_version]
      active_version = _role_profile_registry_select_active_version(profiles: profiles, preferred: preferred)
      _role_profile_registry_bind_context!(profiles: profiles, active_version: active_version)
    rescue StandardError => e
      warn "[AGENT ROLE PROFILE #{@role}] failed to hydrate role profiles: #{e.class}: #{e.message}" if @debug
    end

    def _active_role_profile(version: nil)
      profiles = _role_profile_registry_profiles_for(@role)
      return nil if profiles.empty?

      resolved_version = if version.nil?
                           _role_profile_registry_select_active_version(
                             profiles: profiles,
                             preferred: @context[:role_profile_active_version]
                           )
                         else
                           _role_profile_registry_normalize_version(version)
                         end
      return nil if resolved_version.nil?

      profiles[resolved_version]
    end

    def _role_profile_registry_fetch(role:, version: nil)
      role_name = role.to_s
      return nil if role_name.empty?

      profiles = _role_profile_registry_profiles_for(role_name)
      return nil if profiles.empty?

      if version.nil?
        selected = _role_profile_registry_select_active_version(
          profiles: profiles,
          preferred: role_name == @role ? @context[:role_profile_active_version] : nil
        )
        return selected.nil? ? nil : profiles[selected]
      end

      normalized_version = _role_profile_registry_normalize_version(version)
      return nil if normalized_version.nil?

      profiles[normalized_version]
    end

    def _role_profile_registry_apply!(profile, activate: true, actor: nil, source: "runtime", proposal_id: nil, note: nil)
      normalized = RoleProfile.normalize(profile, expected_role: @role)
      profiles = _role_profile_registry_profiles_for(@role)
      profiles[normalized[:version]] = normalized
      active_version = _role_profile_registry_select_active_version(
        profiles: profiles,
        preferred: activate ? normalized[:version] : @context[:role_profile_active_version]
      )
      _role_profile_registry_bind_context!(profiles: profiles, active_version: active_version)
      _role_profile_registry_persist_role!(
        role: @role,
        profiles: profiles,
        active_version: active_version,
        actor: actor,
        source: source,
        event: "publish",
        proposal_id: proposal_id,
        note: note
      )
      normalized
    end

    def _role_profile_registry_activate!(version:, actor: nil, source: "runtime", proposal_id: nil, note: nil)
      profiles = _role_profile_registry_profiles_for(@role)
      normalized_version = _role_profile_registry_normalize_version(version)
      raise ArgumentError, "role_profile version must be >= 1" if normalized_version.nil?
      raise ArgumentError, "role_profile version #{normalized_version} not found for role '#{@role}'" unless profiles.key?(normalized_version)

      _role_profile_registry_bind_context!(profiles: profiles, active_version: normalized_version)
      _role_profile_registry_persist_role!(
        role: @role,
        profiles: profiles,
        active_version: normalized_version,
        actor: actor,
        source: source,
        event: "activate",
        proposal_id: proposal_id,
        note: note
      )
      profiles[normalized_version]
    end

    def _role_profile_registry_rollback!(version:, actor: nil, source: "runtime", proposal_id: nil, note: nil)
      _role_profile_registry_activate!(
        version: version,
        actor: actor,
        source: source,
        proposal_id: proposal_id,
        note: note
      )
    end

    def _role_profile_registry_profiles_for(role_name)
      role = role_name.to_s
      return {} if role.empty?

      if role == @role
        profiles = _role_profile_registry_profiles_from_context
        return profiles unless profiles.empty?
      end

      payload = _role_profile_registry_role_payload(role)
      _role_profile_registry_normalize_versions(payload["versions"] || payload[:versions], role: role)
    end

    def _role_profile_registry_profiles_from_context
      raw = @context[:role_profiles]
      normalized = _role_profile_registry_normalize_versions(raw, role: @role)
      return normalized unless normalized.empty?

      legacy = @context[:role_profile]
      return {} unless legacy.is_a?(Hash)

      normalized_legacy = RoleProfile.normalize(legacy, expected_role: @role)
      { normalized_legacy[:version] => normalized_legacy }
    rescue ArgumentError
      {}
    end

    def _role_profile_registry_bind_context!(profiles:, active_version:)
      normalized_profiles = profiles.each_with_object({}) do |(version, profile), memo|
        normalized_version = _role_profile_registry_normalize_version(version)
        next if normalized_version.nil?

        memo[normalized_version] = RoleProfile.normalize(profile, expected_role: @role)
      end
      return if normalized_profiles.empty?

      selected = _role_profile_registry_select_active_version(
        profiles: normalized_profiles,
        preferred: active_version
      )
      @context[:role_profiles] = normalized_profiles
      @context[:role_profile_active_version] = selected
      @context[:role_profile] = normalized_profiles[selected]
    end

    def _role_profile_registry_select_active_version(profiles:, preferred:)
      versions = profiles.keys.filter_map { |entry| _role_profile_registry_normalize_version(entry) }.uniq.sort
      return nil if versions.empty?

      preferred_version = _role_profile_registry_normalize_version(preferred)
      return preferred_version if !preferred_version.nil? && profiles.key?(preferred_version)

      versions.max
    end

    def _role_profile_registry_normalize_versions(raw, role:)
      return {} unless raw.is_a?(Hash)

      raw.each_with_object({}) do |(version, profile), memo|
        normalized_version = _role_profile_registry_normalize_version(version)
        next if normalized_version.nil?

        normalized = RoleProfile.normalize(profile, expected_role: role)
        memo[normalized_version] = normalized
      rescue ArgumentError
        next
      end
    end

    def _role_profile_registry_normalize_version(value)
      version = Integer(value)
      return nil if version <= 0

      version
    rescue ArgumentError, TypeError
      nil
    end

    def _role_profile_registry_role_payload(role)
      payload = _role_profile_registry_load_store
      roles = payload["roles"] || payload[:roles]
      return {} unless roles.is_a?(Hash)

      entry = roles[role.to_s] || roles[role.to_sym]
      entry.is_a?(Hash) ? entry : {}
    end

    def _role_profile_registry_load_store
      path = _toolstore_role_profiles_path
      return { "schema_version" => Agent::TOOLSTORE_SCHEMA_VERSION, "roles" => {} } unless File.exist?(path)

      payload = JSON.parse(File.read(path))
      return { "schema_version" => Agent::TOOLSTORE_SCHEMA_VERSION, "roles" => {} } unless payload.is_a?(Hash)

      payload["roles"] = {} unless payload["roles"].is_a?(Hash)
      payload
    rescue JSON::ParserError => e
      _role_profile_registry_quarantine_corrupt_store!(path, e)
      { "schema_version" => Agent::TOOLSTORE_SCHEMA_VERSION, "roles" => {} }
    rescue StandardError => e
      warn "[AGENT ROLE PROFILE #{@role}] failed to load role profile store: #{e.class}: #{e.message}" if @debug
      { "schema_version" => Agent::TOOLSTORE_SCHEMA_VERSION, "roles" => {} }
    end

    def _role_profile_registry_persist_role!(
      role:,
      profiles:,
      active_version:,
      actor:,
      source:,
      event:,
      proposal_id:,
      note:
    )
      payload = _role_profile_registry_load_store
      roles = payload["roles"]
      role_key = role.to_s
      prior = roles[role_key]
      prior_history = prior.is_a?(Hash) ? Array(prior["history"]) : []

      timestamp = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
      history_entry = {
        "event" => event.to_s,
        "active_version" => active_version,
        "source" => source.to_s,
        "actor" => actor.to_s,
        "proposal_id" => proposal_id.to_s,
        "at" => timestamp
      }
      history_entry["note"] = note.to_s unless note.nil?
      history_entry.delete("actor") if history_entry["actor"].empty?
      history_entry.delete("proposal_id") if history_entry["proposal_id"].empty?
      history_entry.delete("note") if history_entry["note"].to_s.empty?

      roles[role_key] = {
        "role" => role_key,
        "active_version" => active_version,
        "versions" => profiles.each_with_object({}) { |(version, profile), memo| memo[version.to_s] = _json_safe(profile) },
        "history" => (prior_history << history_entry).last(200),
        "updated_at" => timestamp
      }
      _role_profile_registry_write_store(payload)
    end

    def _role_profile_registry_write_store(payload)
      path = _toolstore_role_profiles_path
      FileUtils.mkdir_p(File.dirname(path))
      safe_payload = _json_safe(payload)
      safe_payload["schema_version"] = Agent::TOOLSTORE_SCHEMA_VERSION
      safe_payload["roles"] = {} unless safe_payload["roles"].is_a?(Hash)

      temp_path = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.write(temp_path, JSON.generate(safe_payload))
      File.rename(temp_path, path)
    ensure
      File.delete(temp_path) if defined?(temp_path) && temp_path && File.exist?(temp_path)
    end

    def _role_profile_registry_quarantine_corrupt_store!(path, error)
      return unless File.exist?(path)

      quarantined_path = "#{path}.corrupt-#{Time.now.utc.strftime("%Y%m%dT%H%M%S")}"
      FileUtils.mv(path, quarantined_path)
      if @debug
        warn(
          "[AGENT ROLE PROFILE #{@role}] quarantined corrupt role profile store: " \
          "#{File.basename(quarantined_path)} (#{error.class})"
        )
      end
    rescue StandardError => e
      warn "[AGENT ROLE PROFILE #{@role}] failed to quarantine role profile store: #{e.class}: #{e.message}" if @debug
    end
  end
end
