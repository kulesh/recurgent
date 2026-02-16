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

      {
        status: _conversation_history_value(raw_summary, :status)&.to_s || "unknown",
        ok: !!_conversation_history_value(raw_summary, :ok),
        error_type: _conversation_history_value(raw_summary, :error_type),
        retriable: !!_conversation_history_value(raw_summary, :retriable),
        value_class: _conversation_history_value(raw_summary, :value_class)&.to_s
      }.compact
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
