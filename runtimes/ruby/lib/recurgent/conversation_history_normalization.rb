# frozen_string_literal: true

class Agent
  # Agent::ConversationHistoryNormalization — tolerant canonicalization for history records.
  module ConversationHistoryNormalization
    private

    def _normalize_conversation_history_store!(history)
      normalized = history.filter_map { |entry| _normalize_conversation_history_entry(entry) }
      dropped_count = history.length - normalized.length
      warn "[AGENT HISTORY #{@role}] dropped #{dropped_count} non-canonical conversation history entries" if dropped_count.positive? && @debug

      @context[:conversation_history] = normalized
    end

    def _normalize_conversation_history_entry(entry)
      return nil unless _conversation_history_record_like?(entry)

      {
        call_id: _conversation_history_value(entry, :call_id)&.to_s,
        timestamp: _conversation_history_value(entry, :timestamp)&.to_s,
        speaker: _normalize_conversation_history_speaker(_conversation_history_value(entry, :speaker)),
        method_name: _conversation_history_value(entry, :method_name)&.to_s,
        args: _normalize_conversation_history_args(_conversation_history_value(entry, :args)),
        kwargs: _normalize_conversation_history_kwargs(_conversation_history_value(entry, :kwargs)),
        outcome_summary: _normalize_conversation_history_outcome_summary(entry),
        trace_id: _conversation_history_value(entry, :trace_id)&.to_s,
        parent_call_id: _conversation_history_value(entry, :parent_call_id)&.to_s,
        depth: _normalize_conversation_history_depth(_conversation_history_value(entry, :depth)),
        duration_ms: _normalize_conversation_history_duration(_conversation_history_value(entry, :duration_ms))
      }
    end

    def _conversation_history_record_like?(entry)
      return false unless entry.is_a?(Hash)

      entry.key?(:method_name) || entry.key?("method_name") ||
        entry.key?(:outcome_summary) || entry.key?("outcome_summary") ||
        entry.key?(:call_id) || entry.key?("call_id")
    end

    def _normalize_conversation_history_outcome_summary(entry)
      raw_summary = _conversation_history_value(entry, :outcome_summary)
      return { status: "unknown", ok: false, error_type: nil, retriable: false } unless raw_summary.is_a?(Hash)

      _normalize_conversation_history_outcome_summary_base(raw_summary)
        .merge(_normalize_conversation_history_outcome_summary_provenance(raw_summary))
    end

    def _normalize_conversation_history_outcome_summary_base(raw_summary)
      {
        status: _conversation_history_value(raw_summary, :status)&.to_s || "unknown",
        ok: _conversation_history_truthy?(_conversation_history_value(raw_summary, :ok)),
        error_type: _conversation_history_value(raw_summary, :error_type),
        retriable: _conversation_history_truthy?(_conversation_history_value(raw_summary, :retriable)),
        value_class: _conversation_history_value(raw_summary, :value_class)&.to_s
      }.compact
    end

    def _normalize_conversation_history_outcome_summary_provenance(raw_summary)
      source_count = _normalize_conversation_history_source_count(_conversation_history_value(raw_summary, :source_count))
      primary_uri = _normalize_conversation_history_optional_string(_conversation_history_value(raw_summary, :primary_uri))
      retrieval_mode = _normalize_conversation_history_optional_string(_conversation_history_value(raw_summary, :retrieval_mode))

      normalized = {}
      normalized[:source_count] = source_count unless source_count.nil?
      normalized[:primary_uri] = primary_uri unless primary_uri.nil?
      normalized[:retrieval_mode] = retrieval_mode unless retrieval_mode.nil?
      normalized
    end

    def _normalize_conversation_history_source_count(value)
      return nil if value.nil?

      parsed = value.is_a?(Integer) ? value : Integer(value, 10)
      return nil if parsed.negative?

      parsed
    rescue ArgumentError, TypeError
      nil
    end

    def _normalize_conversation_history_optional_string(value)
      return nil if value.nil?

      text = value.to_s.strip
      return nil if text.empty?

      _normalize_utf8(text)
    end

    def _conversation_history_truthy?(value)
      value ? true : false
    end

    def _normalize_conversation_history_speaker(value)
      normalized = value&.to_s
      return normalized if %w[user tool].include?(normalized)

      nil
    end

    def _normalize_conversation_history_args(value)
      return [] if value.nil?
      return _conversation_history_safe(value) if value.is_a?(Array)

      [_conversation_history_safe(value)]
    end

    def _normalize_conversation_history_kwargs(value)
      return {} if value.nil?
      return _conversation_history_safe(value) if value.is_a?(Hash)

      { value: _conversation_history_safe(value) }
    end

    def _normalize_conversation_history_depth(value)
      return nil if value.nil?
      return value.to_i if value.is_a?(Numeric) || value.to_s.match?(/\A-?\d+\z/)

      nil
    end

    def _normalize_conversation_history_duration(value)
      return nil if value.nil?

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
