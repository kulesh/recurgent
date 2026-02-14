# frozen_string_literal: true

class Agent
  class DependencyManifest
    GEM_NAME_PATTERN = /\A[a-zA-Z0-9_-]+\z/

    def self.normalize!(dependencies)
      _normalize_entries(_validate_dependencies_container(dependencies))
    end

    def self._extract_name(entry, index)
      raw_name = entry[:name] || entry["name"]
      unless raw_name.is_a?(String) && !raw_name.strip.empty?
        raise InvalidDependencyManifestError, "dependencies[#{index}].name must be a non-empty String"
      end

      name = raw_name.strip.downcase
      raise InvalidDependencyManifestError, "dependencies[#{index}].name is invalid: #{raw_name.inspect}" unless name.match?(GEM_NAME_PATTERN)

      name
    end

    def self._extract_version(entry, index)
      raw_version = entry.key?(:version) ? entry[:version] : entry["version"]
      return ">= 0" if raw_version.nil?

      unless raw_version.is_a?(String) && !raw_version.strip.empty?
        raise InvalidDependencyManifestError, "dependencies[#{index}].version must be a non-empty String when provided"
      end

      raw_version.strip
    end

    def self._validate_dependencies_container(dependencies)
      return [] if dependencies.nil?
      raise InvalidDependencyManifestError, "dependencies must be an Array" unless dependencies.is_a?(Array)

      dependencies
    end

    def self._normalize_entries(entries)
      versions_by_name = {}
      normalized = []

      entries.each_with_index do |entry, index|
        name, version = _normalize_entry(entry, index)
        _register_entry!(versions_by_name, normalized, name, version, index)
      end

      normalized.sort_by! { |dep| [dep[:name], dep[:version]] }
      normalized.each(&:freeze)
      normalized.freeze
    end

    def self._normalize_entry(entry, index)
      raise InvalidDependencyManifestError, "dependencies[#{index}] must be an object" unless entry.is_a?(Hash)

      name = _extract_name(entry, index)
      version = _extract_version(entry, index)
      [name, version]
    end

    def self._register_entry!(versions_by_name, normalized, name, version, index)
      existing = versions_by_name[name]
      if existing && existing != version
        raise InvalidDependencyManifestError,
              "dependencies[#{index}] conflicts with prior declaration for gem '#{name}' (#{existing} vs #{version})"
      end

      return if existing

      versions_by_name[name] = version
      normalized << { name: name, version: version }
    end
  end
end
