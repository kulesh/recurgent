# frozen_string_literal: true

class Agent
  # Agent::AttemptTracking — per-attempt snapshot/restore helpers for safe retry loops
  # and failed attempt diagnostics across recovery lanes.
  module AttemptTracking
    ATTEMPT_FAILURE_STAGES = %w[validation execution outcome_policy].freeze
    MAX_ATTEMPT_FAILURES_RECORDED = 8
    MAX_FAILURE_MESSAGE_LENGTH = 400

    private

    # -- Attempt isolation (snapshot/restore) -----------------------------------

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

    # -- Failure telemetry -----------------------------------------------------

    def _record_attempt_failure_from_error!(state:, stage:, error:)
      _record_attempt_failure!(
        state: state,
        stage: stage,
        error_class: error.class.name,
        error_message: error.message.to_s
      )
    end

    def _record_attempt_failure_from_outcome!(state:, stage:, outcome:)
      _record_attempt_failure!(
        state: state,
        stage: stage,
        error_class: "Agent::OutcomeError",
        error_message: "#{outcome.error_type}: #{outcome.error_message}"
      )
    end

    def _record_attempt_failure!(state:, stage:, error_class:, error_message:)
      normalized_stage = _normalize_attempt_failure_stage(stage)
      call_id = _call_stack.last&.fetch(:call_id, nil)
      entry = {
        attempt_id: state.attempt_id,
        stage: normalized_stage,
        error_class: error_class.to_s,
        error_message: _truncate_failure_message(error_message),
        timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
        call_id: call_id
      }
      failures = Array(state.attempt_failures)
      failures << entry
      state.attempt_failures = failures.last(MAX_ATTEMPT_FAILURES_RECORDED)
      state.latest_failure_stage = normalized_stage
      state.latest_failure_class = entry[:error_class]
      state.latest_failure_message = entry[:error_message]
    end

    def _normalize_attempt_failure_stage(stage)
      candidate = stage.to_s
      ATTEMPT_FAILURE_STAGES.include?(candidate) ? candidate : "execution"
    end

    def _truncate_failure_message(message)
      normalized = _normalize_utf8(message.to_s)
      return normalized if normalized.length <= MAX_FAILURE_MESSAGE_LENGTH

      "#{normalized[0, MAX_FAILURE_MESSAGE_LENGTH - 3]}..."
    end
  end
end
