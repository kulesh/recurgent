# frozen_string_literal: true

require "digest"
require "time"

class Agent
  # Agent::ContentStore — bounded response-content continuity substrate.
  # rubocop:disable Metrics/ModuleLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Naming/PredicateMethod
  module ContentStore
    CONTENT_REF_PREFIX = "content:"
    CONTENT_STORE_ENTRY_SOURCE = "outcome_value"
    CONTENT_STORE_READ_TRACE_KEY = :__recurgent_content_store_read_trace

    private

    def _store_outcome_content_for_history(outcome:, call_context:)
      return _content_store_skip_result(reason: "invalid_outcome") unless outcome.is_a?(Outcome)

      should_store, reason = _content_store_should_store_for_call(outcome: outcome, call_context: call_context)
      return _content_store_skip_result(reason: reason) unless should_store

      payload = _content_store_payload_for_outcome(outcome)
      serialized = _content_store_serialize_payload(payload)
      return _content_store_skip_result(reason: serialized[:reason]) unless serialized[:ok]

      bytes = serialized[:bytes]
      max_bytes = _content_store_max_bytes
      return _content_store_skip_result(reason: "entry_exceeds_max_bytes") if bytes > max_bytes

      store = _content_store_state
      evicted_count = _content_store_evict_expired!(store)

      ref = "#{CONTENT_REF_PREFIX}#{SecureRandom.hex(12)}"
      now = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
      entry = {
        ref: ref,
        call_id: call_context&.fetch(:call_id, nil),
        trace_id: call_context&.fetch(:trace_id, nil),
        parent_call_id: call_context&.fetch(:parent_call_id, nil),
        depth: call_context&.fetch(:depth, 0).to_i,
        role: @role.to_s,
        source: CONTENT_STORE_ENTRY_SOURCE,
        method_name: Agent.current_outcome_context[:method_name]&.to_s,
        created_at: now,
        last_accessed_at: now,
        content_kind: serialized[:content_kind],
        content_bytes: bytes,
        content_digest: serialized[:content_digest],
        serialization_mode: serialized[:serialization_mode],
        value_class: outcome.value.class.name,
        payload_json: serialized[:payload_json]
      }

      _content_store_insert!(store, entry)
      evicted_count += _content_store_enforce_bounds!(store)

      {
        stored: true,
        content_ref: ref,
        content_kind: serialized[:content_kind],
        content_bytes: bytes,
        content_digest: serialized[:content_digest],
        serialization_mode: serialized[:serialization_mode],
        content_store_eviction_count: evicted_count,
        content_store_entry_count: store[:order].size,
        content_store_total_bytes: store[:total_bytes]
      }
    rescue StandardError => e
      warn "[AGENT CONTENT STORE #{@role}] write failed: #{e.class}: #{e.message}" if @debug
      _content_store_skip_result(reason: "store_write_failed")
    end

    def _resolve_content_ref(ref)
      normalized_ref = ref.to_s.strip
      return nil if normalized_ref.empty?

      store = _content_store_state
      _content_store_evict_expired!(store)
      entry = store[:entries][normalized_ref]
      unless entry.is_a?(Hash)
        _content_store_record_read(ref: normalized_ref, hit: false)
        return nil
      end

      entry[:last_accessed_at] = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
      _content_store_touch_ref!(store, normalized_ref)
      payload = JSON.parse(entry.fetch(:payload_json))
      _content_store_record_read(ref: normalized_ref, hit: true)
      payload
    rescue JSON::ParserError
      _content_store_record_read(ref: normalized_ref, hit: false)
      nil
    rescue StandardError => e
      warn "[AGENT CONTENT STORE #{@role}] read failed for #{normalized_ref}: #{e.class}: #{e.message}" if @debug
      _content_store_record_read(ref: normalized_ref, hit: false)
      nil
    end

    def _content_store_should_store_for_call(outcome:, call_context:)
      return [false, "unknown_outcome_status"] unless outcome.respond_to?(:ok?) && outcome.respond_to?(:error?)
      return [true, nil] if outcome.ok? && _content_store_depth_allows_write?(call_context: call_context)
      return [true, nil] if outcome.error? && @runtime_config.fetch(:content_store_store_error_payloads, false)

      if outcome.ok?
        [false, "nested_capture_disabled"]
      else
        [false, "error_payload_capture_disabled"]
      end
    end

    def _content_store_depth_allows_write?(call_context:)
      depth = call_context&.fetch(:depth, 0).to_i
      return true if depth <= 0

      @runtime_config.fetch(:content_store_nested_capture_enabled, false)
    end

    def _content_store_payload_for_outcome(outcome)
      return outcome.value if outcome.ok?

      {
        error_type: outcome.error_type,
        error_message: outcome.error_message,
        retriable: outcome.retriable,
        metadata: outcome.metadata
      }
    end

    def _content_store_serialize_payload(payload)
      normalized_payload = _content_store_json_safe(payload)
      payload_json = JSON.generate(normalized_payload)
      {
        ok: true,
        payload_json: payload_json,
        bytes: payload_json.bytesize,
        serialization_mode: "json_safe",
        content_kind: _content_store_kind(normalized_payload),
        content_digest: "sha256:#{Digest::SHA256.hexdigest(payload_json)}"
      }
    rescue JSON::GeneratorError, TypeError
      fallback_payload = {
        "__content_fallback__" => true,
        "representation" => payload.inspect
      }
      payload_json = JSON.generate(fallback_payload)
      {
        ok: true,
        payload_json: payload_json,
        bytes: payload_json.bytesize,
        serialization_mode: "fallback_inspect",
        content_kind: "fallback",
        content_digest: "sha256:#{Digest::SHA256.hexdigest(payload_json)}"
      }
    rescue StandardError
      { ok: false, reason: "serialization_failed" }
    end

    def _content_store_json_safe(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, entry), normalized|
          normalized[key.to_s] = _content_store_json_safe(entry)
        end
      when Array
        value.map { |entry| _content_store_json_safe(entry) }
      when String
        _normalize_utf8(value)
      when Symbol
        value.to_s
      when Float
        value.finite? ? value : value.to_s
      when Integer, TrueClass, FalseClass, NilClass
        value
      else
        value.respond_to?(:to_h) ? _content_store_json_safe(value.to_h) : value.inspect
      end
    end

    def _content_store_kind(payload)
      case payload
      when Hash
        "object"
      when Array
        "array"
      when String
        "string"
      when Numeric
        "number"
      when TrueClass, FalseClass
        "boolean"
      when NilClass
        "null"
      else
        "scalar"
      end
    end

    def _content_store_state
      @content_store_state ||= {
        entries: {},
        order: [],
        total_bytes: 0
      }
    end

    def _content_store_insert!(store, entry)
      ref = entry.fetch(:ref)
      store[:entries][ref] = entry
      store[:order] << ref
      store[:total_bytes] += entry.fetch(:content_bytes).to_i
    end

    def _content_store_enforce_bounds!(store)
      evicted = 0
      max_entries = _content_store_max_entries
      max_bytes = _content_store_max_bytes
      while store[:order].size > max_entries || store[:total_bytes] > max_bytes
        ref = store[:order].shift
        break if ref.nil?

        next unless _content_store_delete_ref!(store, ref)

        evicted += 1
      end
      evicted
    end

    def _content_store_evict_expired!(store)
      ttl = _content_store_ttl_seconds
      return 0 unless ttl.is_a?(Integer) && ttl.positive?

      now = Time.now.utc
      evicted = 0
      store[:order].dup.each do |ref|
        entry = store[:entries][ref]
        next unless entry.is_a?(Hash)

        created_at = entry[:created_at].to_s
        created = Time.parse(created_at)
        next if (now - created) <= ttl

        next unless _content_store_delete_ref!(store, ref)

        evicted += 1
      rescue ArgumentError
        next unless _content_store_delete_ref!(store, ref)

        evicted += 1
      end
      evicted
    end

    def _content_store_delete_ref!(store, ref)
      entry = store[:entries].delete(ref)
      return false unless entry.is_a?(Hash)

      store[:order].delete(ref)
      store[:total_bytes] -= entry.fetch(:content_bytes, 0).to_i
      store[:total_bytes] = 0 if store[:total_bytes].negative?
      true
    end

    def _content_store_touch_ref!(store, ref)
      store[:order].delete(ref)
      store[:order] << ref
    end

    def _content_store_max_entries
      @runtime_config.fetch(:content_store_max_entries, 128).to_i
    end

    def _content_store_max_bytes
      @runtime_config.fetch(:content_store_max_bytes, 2_097_152).to_i
    end

    def _content_store_ttl_seconds
      value = @runtime_config.fetch(:content_store_ttl_seconds, nil)
      return nil if value.nil?

      value.to_i
    end

    def _content_store_skip_result(reason:)
      store = _content_store_state
      {
        stored: false,
        content_store_write_skipped_reason: reason,
        content_store_eviction_count: 0,
        content_store_entry_count: store[:order].size,
        content_store_total_bytes: store[:total_bytes]
      }
    end

    def _content_store_reset_read_trace!
      Thread.current[CONTENT_STORE_READ_TRACE_KEY] = {
        hits: 0,
        misses: 0,
        refs: []
      }
    end

    def _content_store_read_trace_snapshot
      trace = Thread.current[CONTENT_STORE_READ_TRACE_KEY]
      return { hits: 0, misses: 0, refs: [] } unless trace.is_a?(Hash)

      {
        hits: trace[:hits].to_i,
        misses: trace[:misses].to_i,
        refs: Array(trace[:refs]).map(&:to_s).reject(&:empty?).uniq
      }
    end

    def _content_store_record_read(ref:, hit:)
      trace = Thread.current[CONTENT_STORE_READ_TRACE_KEY]
      return unless trace.is_a?(Hash)

      if hit
        trace[:hits] = trace[:hits].to_i + 1
      else
        trace[:misses] = trace[:misses].to_i + 1
      end
      trace[:refs] = Array(trace[:refs])
      trace[:refs] << ref.to_s
    end
  end
  # rubocop:enable Metrics/ModuleLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Naming/PredicateMethod
end
