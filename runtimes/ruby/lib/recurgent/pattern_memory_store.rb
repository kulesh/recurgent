# frozen_string_literal: true

class Agent
  # Agent::PatternMemoryStore — bounded cross-session capability-pattern event memory.
  module PatternMemoryStore
    PATTERN_MEMORY_SCHEMA_VERSION = 1
    PATTERN_MEMORY_RETENTION = 50

    private

    def _record_pattern_memory_event(method_name:, state:, call_context:)
      return unless _record_pattern_memory_for_source?(state.program_source)

      timestamp = Time.now.utc
      user_correction = _detect_temporal_reask_user_correction(
        method_name: method_name,
        state: state,
        call_context: call_context,
        timestamp: timestamp
      )
      _capture_user_correction_state!(state, user_correction)
      _pattern_memory_append_event(
        role: @role,
        event: _build_pattern_memory_event(
          method_name: method_name,
          state: state,
          call_context: call_context,
          timestamp: timestamp,
          user_correction: user_correction
        )
      )
    rescue StandardError => e
      warn "[AGENT PATTERNS #{@role}.#{method_name}] failed to persist pattern memory: #{e.class}: #{e.message}" if @debug
    end

    def _build_pattern_memory_event(method_name:, state:, call_context:, timestamp:, user_correction:)
      event = {
        "timestamp" => timestamp.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
        "recorded_at_ms" => (timestamp.to_f * 1000).to_i,
        "role" => @role,
        "method_name" => method_name.to_s,
        "trace_id" => call_context&.fetch(:trace_id, nil),
        "call_id" => call_context&.fetch(:call_id, nil),
        "parent_call_id" => call_context&.fetch(:parent_call_id, nil),
        "depth" => call_context&.fetch(:depth, nil),
        "had_delegated_calls" => call_context&.fetch(:had_child_calls, false) == true,
        "capability_patterns" => Array(state.capability_patterns).map(&:to_s).uniq,
        "outcome_status" => state.outcome&.status,
        "error_type" => state.outcome&.error_type
      }
      event["user_correction"] = user_correction if user_correction&.fetch("detected", false)
      event
    end

    def _record_pattern_memory_for_source?(program_source)
      %w[generated repaired].include?(program_source.to_s)
    end

    def _pattern_memory_recent_events(role:, method_name:, window:)
      store = _pattern_memory_load
      role_bucket = store.fetch("roles", {}).fetch(role.to_s, {})
      events = Array(role_bucket["events"])
      events.select! { |event| event["method_name"].to_s == method_name.to_s }
      events.last(window)
    end

    def _pattern_memory_append_event(role:, event:)
      store = _pattern_memory_load
      roles = store["roles"] ||= {}
      role_bucket = roles[role.to_s] ||= { "events" => [] }
      events = Array(role_bucket["events"])
      events << event
      role_bucket["events"] = events.last(PATTERN_MEMORY_RETENTION)
      _pattern_memory_write(store)
    end

    def _pattern_memory_load
      path = _toolstore_patterns_path
      return _pattern_memory_template unless File.exist?(path)

      parsed = JSON.parse(File.read(path))
      return _pattern_memory_template unless _pattern_memory_schema_supported?(parsed["schema_version"])

      _pattern_memory_normalize(parsed)
    rescue JSON::ParserError => e
      _pattern_memory_quarantine_corrupt_file!(path, e)
      _pattern_memory_template
    rescue StandardError => e
      warn "[AGENT PATTERNS #{@role}] failed to load pattern store: #{e.class}: #{e.message}" if @debug
      _pattern_memory_template
    end

    def _pattern_memory_write(store)
      path = _toolstore_patterns_path
      FileUtils.mkdir_p(File.dirname(path))
      payload = {
        "schema_version" => PATTERN_MEMORY_SCHEMA_VERSION,
        "roles" => _json_safe(store.fetch("roles", {}))
      }

      temp_path = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.write(temp_path, JSON.generate(payload))
      File.rename(temp_path, path)
    ensure
      File.delete(temp_path) if defined?(temp_path) && temp_path && File.exist?(temp_path)
    end

    def _pattern_memory_template
      {
        "schema_version" => PATTERN_MEMORY_SCHEMA_VERSION,
        "roles" => {}
      }
    end

    def _pattern_memory_schema_supported?(schema_version)
      return true if schema_version.nil?
      return true if schema_version.to_i == PATTERN_MEMORY_SCHEMA_VERSION

      warn "[AGENT PATTERNS #{@role}] ignored pattern store schema=#{schema_version}" if @debug
      false
    end

    def _pattern_memory_normalize(parsed)
      raw_roles = parsed.fetch("roles", {})
      normalized_roles = {}
      return { "schema_version" => PATTERN_MEMORY_SCHEMA_VERSION, "roles" => normalized_roles } unless raw_roles.is_a?(Hash)

      raw_roles.each do |role, role_bucket|
        next unless role_bucket.is_a?(Hash)

        normalized_roles[role.to_s] = {
          "events" => Array(role_bucket["events"]).map { |event| _pattern_memory_normalize_event(event) }.compact
        }
      end

      {
        "schema_version" => PATTERN_MEMORY_SCHEMA_VERSION,
        "roles" => normalized_roles
      }
    end

    def _pattern_memory_normalize_event(event)
      return nil unless event.is_a?(Hash)

      _pattern_memory_normalize_event_base(event)
        .merge(_pattern_memory_normalize_event_trace(event))
        .merge(_pattern_memory_normalize_event_outcome(event))
    end

    def _pattern_memory_normalize_event_base(event)
      {
        "timestamp" => event["timestamp"].to_s,
        "recorded_at_ms" => event["recorded_at_ms"].to_i,
        "role" => event["role"].to_s,
        "method_name" => event["method_name"].to_s,
        "capability_patterns" => Array(event["capability_patterns"]).map(&:to_s).uniq
      }
    end

    def _pattern_memory_normalize_event_trace(event)
      {
        "trace_id" => event["trace_id"]&.to_s,
        "call_id" => event["call_id"]&.to_s,
        "parent_call_id" => event["parent_call_id"]&.to_s,
        "depth" => event["depth"],
        "had_delegated_calls" => event["had_delegated_calls"] == true
      }
    end

    def _pattern_memory_normalize_event_outcome(event)
      {
        "outcome_status" => event["outcome_status"],
        "error_type" => event["error_type"],
        "user_correction" => _pattern_memory_normalize_user_correction(event["user_correction"])
      }
    end

    def _pattern_memory_quarantine_corrupt_file!(path, error)
      return unless File.exist?(path)

      quarantined_path = "#{path}.corrupt-#{Time.now.utc.strftime("%Y%m%dT%H%M%S")}"
      FileUtils.mv(path, quarantined_path)
      return unless @debug

      warn "[AGENT PATTERNS #{@role}] quarantined corrupt pattern store: #{File.basename(quarantined_path)} (#{error.class})"
    rescue StandardError => e
      warn "[AGENT PATTERNS #{@role}] failed to quarantine corrupt pattern store: #{e.message}" if @debug
    end
  end
end
