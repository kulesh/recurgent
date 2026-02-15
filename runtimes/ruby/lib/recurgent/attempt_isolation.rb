# frozen_string_literal: true

class Agent
  # Agent::AttemptIsolation — per-attempt snapshot/restore helpers for safe retry loops.
  module AttemptIsolation
    private

    def _capture_attempt_snapshot
      {
        context: _deep_clone_attempt_state(@context),
        tool_registry: _snapshot_file_content(_toolstore_registry_path)
      }
    end

    def _restore_attempt_snapshot!(snapshot)
      @context = _deep_clone_attempt_state(snapshot[:context] || {})
      _restore_file_content(_toolstore_registry_path, snapshot[:tool_registry])
    end

    def _snapshot_file_content(path)
      return { exists: false } unless File.exist?(path)

      { exists: true, content: File.binread(path) }
    rescue StandardError
      { exists: false, content: nil }
    end

    def _restore_file_content(path, snapshot)
      return unless snapshot.is_a?(Hash)

      if snapshot[:exists]
        temp_path = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(temp_path, snapshot[:content].to_s)
        File.rename(temp_path, path)
      else
        FileUtils.rm_f(path)
      end
    ensure
      FileUtils.rm_f(temp_path) if defined?(temp_path) && temp_path
    end

    def _deep_clone_attempt_state(value, seen = nil)
      seen ||= {}.compare_by_identity

      case value
      when nil, Numeric, Symbol, TrueClass, FalseClass
        value
      when String
        value.dup
      when Array
        _clone_array_attempt_state(value, seen)
      when Hash
        _clone_hash_attempt_state(value, seen)
      else
        value.respond_to?(:dup) ? value.dup : value
      end
    end

    def _clone_array_attempt_state(array, seen)
      return seen[array] if seen.key?(array)

      clone = []
      seen[array] = clone
      array.each { |entry| clone << _deep_clone_attempt_state(entry, seen) }
      clone
    end

    def _clone_hash_attempt_state(hash, seen)
      return seen[hash] if seen.key?(hash)

      clone = {}
      seen[hash] = clone
      hash.each do |key, entry|
        clone[_deep_clone_attempt_state(key, seen)] = _deep_clone_attempt_state(entry, seen)
      end
      clone
    end
  end
end
