# frozen_string_literal: true

class Agent
  # Agent::ConversationHistory — canonical structured call-history records stored in context.
  # rubocop:disable Metrics/ModuleLength
  module ConversationHistory
    include ConversationHistoryNormalization

    private

    # rubocop:disable Metrics/AbcSize
    def _append_conversation_history_record!(method_name:, args:, kwargs:, duration_ms:, call_context:, outcome:)
      history = _conversation_history_store
      record = _conversation_history_record(
        method_name: method_name,
        args: args,
        kwargs: kwargs,
        duration_ms: duration_ms,
        call_context: call_context,
        outcome: outcome
      )
      history << record
      outcome_summary = _conversation_history_value(record, :outcome_summary)
      content_ref = _conversation_history_value(outcome_summary, :content_ref)
      content_store_write = _consume_last_content_store_write_result
      {
        appended: true,
        size: history.size,
        content_store_write_applied: !content_ref.to_s.strip.empty?,
        content_store_write_ref: content_ref&.to_s,
        content_store_write_kind: _conversation_history_value(outcome_summary, :content_kind)&.to_s,
        content_store_write_bytes: _conversation_history_value(outcome_summary, :content_bytes),
        content_store_write_digest: _conversation_history_value(outcome_summary, :content_digest)&.to_s,
        content_store_write_skipped_reason: content_store_write[:content_store_write_skipped_reason],
        content_store_eviction_count: content_store_write[:content_store_eviction_count],
        content_store_entry_count: _content_store_state.fetch(:order, []).size,
        content_store_total_bytes: _content_store_state.fetch(:total_bytes, 0)
      }
    rescue StandardError => e
      warn "[AGENT HISTORY #{@role}.#{method_name}] #{e.class}: #{e.message}" if @debug
      size = @context[:conversation_history].is_a?(Array) ? @context[:conversation_history].size : 0
      {
        appended: false,
        size: size,
        content_store_write_applied: false,
        content_store_write_ref: nil,
        content_store_write_kind: nil,
        content_store_write_bytes: nil,
        content_store_write_digest: nil,
        content_store_write_skipped_reason: "history_append_failed",
        content_store_eviction_count: 0,
        content_store_entry_count: _content_store_state.fetch(:order, []).size,
        content_store_total_bytes: _content_store_state.fetch(:total_bytes, 0)
      }
    end
    # rubocop:enable Metrics/AbcSize

    def _conversation_history_store
      history = @context[:conversation_history]
      return @context[:conversation_history] = [] if history.nil?

      unless history.is_a?(Array)
        warn "[AGENT HISTORY #{@role}] coercing malformed context[:conversation_history] to []" if @debug
        return @context[:conversation_history] = []
      end

      _normalize_conversation_history_store!(history)
    end

    def _conversation_history_records
      _conversation_history_store
    end

    def _conversation_history_preview(limit: Agent::CONVERSATION_HISTORY_PROMPT_PREVIEW_LIMIT)
      _conversation_history_records.last(limit).map do |record|
        _conversation_history_preview_record(record)
      end
    end

    def _conversation_history_record(method_name:, args:, kwargs:, duration_ms:, call_context:, outcome:)
      {
        call_id: call_context&.fetch(:call_id, nil),
        timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
        speaker: _conversation_history_speaker(call_context),
        method_name: method_name.to_s,
        args: _conversation_history_safe(args),
        kwargs: _conversation_history_safe(kwargs),
        outcome_summary: _conversation_history_outcome_summary(outcome, call_context: call_context),
        trace_id: call_context&.fetch(:trace_id, nil),
        parent_call_id: call_context&.fetch(:parent_call_id, nil),
        depth: call_context&.fetch(:depth, nil),
        duration_ms: duration_ms.round(1)
      }
    end

    def _conversation_history_preview_record(record)
      return {} unless record.is_a?(Hash)

      outcome_summary = _conversation_history_value(record, :outcome_summary)
      {
        call_id: _conversation_history_value(record, :call_id),
        speaker: _conversation_history_value(record, :speaker),
        method_name: _conversation_history_value(record, :method_name),
        outcome_status: _conversation_history_value(outcome_summary, :status),
        error_type: _conversation_history_value(outcome_summary, :error_type)
      }
    end

    def _conversation_history_speaker(call_context)
      depth = call_context&.fetch(:depth, 0).to_i
      depth.zero? ? "user" : "tool"
    end

    def _conversation_history_outcome_summary(outcome, call_context:)
      return { status: "unknown", ok: false, error_type: "unknown", retriable: false } unless outcome.is_a?(Outcome)

      summary = {
        status: outcome.status.to_s,
        ok: outcome.ok?,
        error_type: outcome.error_type,
        retriable: outcome.retriable
      }
      summary.merge!(_conversation_history_provenance_summary(outcome.value)) if outcome.ok?
      should_capture_content = outcome.ok? || @runtime_config.fetch(:content_store_store_error_payloads, false)
      summary.merge!(_conversation_history_content_summary(outcome: outcome, call_context: call_context)) if should_capture_content
      summary[:value_class] = outcome.value.class.name unless outcome.value.nil?
      summary
    end

    def _conversation_history_content_summary(outcome:, call_context:)
      storage = _store_outcome_content_for_history(outcome: outcome, call_context: call_context)
      @_last_content_store_write_result = storage
      return {} unless storage[:stored]

      {
        content_ref: storage[:content_ref],
        content_kind: storage[:content_kind],
        content_bytes: storage[:content_bytes],
        content_digest: storage[:content_digest]
      }.compact
    end

    def _consume_last_content_store_write_result
      value = @_last_content_store_write_result
      @_last_content_store_write_result = nil
      return {} unless value.is_a?(Hash)

      value
    end

    def _conversation_history_provenance_summary(value)
      provenance = _conversation_history_extract_provenance(value)
      return {} unless provenance.is_a?(Hash)

      sources = _conversation_history_value(provenance, :sources)
      return {} unless sources.is_a?(Array)

      source_entries = sources.select { |entry| entry.is_a?(Hash) }
      return {} if source_entries.empty?

      first_source = source_entries.first
      primary_uri = _conversation_history_value(first_source, :uri)
      retrieval_mode = _conversation_history_value(first_source, :retrieval_mode)

      summary = { source_count: source_entries.length }
      summary[:primary_uri] = _normalize_utf8(primary_uri.to_s) unless primary_uri.to_s.strip.empty?
      summary[:retrieval_mode] = retrieval_mode.to_s unless retrieval_mode.to_s.strip.empty?
      summary
    end

    def _conversation_history_extract_provenance(value)
      return nil unless value.is_a?(Hash)

      _conversation_history_value(value, :provenance)
    end

    def _conversation_history_safe(value)
      case value
      when Array
        _conversation_history_safe_array(value)
      when Hash
        _conversation_history_safe_hash(value)
      else
        _conversation_history_safe_scalar(value)
      end
    end

    def _conversation_history_safe_array(value)
      value.map { |entry| _conversation_history_safe(entry) }
    end

    def _conversation_history_safe_hash(value)
      value.each_with_object({}) do |(key, entry), normalized|
        normalized[_conversation_history_safe_key(key)] = _conversation_history_safe(entry)
      end
    end

    def _conversation_history_safe_scalar(value)
      return value if value.nil? || value.is_a?(Numeric) || value.is_a?(TrueClass) || value.is_a?(FalseClass)
      return value.to_s if value.is_a?(Symbol)
      return _normalize_utf8(value) if value.is_a?(String)

      value.inspect
    end

    def _conversation_history_safe_key(key)
      return key if key.is_a?(Symbol)
      return _normalize_utf8(key) if key.is_a?(String)

      key.to_s
    end

    def _conversation_history_value(hash_value, key)
      return nil unless hash_value.is_a?(Hash)

      hash_value[key] || hash_value[key.to_s]
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
