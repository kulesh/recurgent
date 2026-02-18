# frozen_string_literal: true

class Agent
  # Agent::ConversationHistory — canonical structured call-history records stored in context.
  module ConversationHistory
    private

    def _append_conversation_history_record!(method_name:, args:, kwargs:, duration_ms:, call_context:, outcome:)
      history = _conversation_history_store
      history << _conversation_history_record(
        method_name: method_name,
        args: args,
        kwargs: kwargs,
        duration_ms: duration_ms,
        call_context: call_context,
        outcome: outcome
      )
      { appended: true, size: history.size }
    rescue StandardError => e
      warn "[AGENT HISTORY #{@role}.#{method_name}] #{e.class}: #{e.message}" if @debug
      size = @context[:conversation_history].is_a?(Array) ? @context[:conversation_history].size : 0
      { appended: false, size: size }
    end

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
        outcome_summary: _conversation_history_outcome_summary(outcome),
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

    def _conversation_history_outcome_summary(outcome)
      return { status: "unknown", ok: false, error_type: "unknown", retriable: false } unless outcome.is_a?(Outcome)

      summary = {
        status: outcome.status.to_s,
        ok: outcome.ok?,
        error_type: outcome.error_type,
        retriable: outcome.retriable
      }
      summary.merge!(_conversation_history_provenance_summary(outcome.value)) if outcome.ok?
      summary[:value_class] = outcome.value.class.name unless outcome.value.nil?
      summary
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

    # --- Normalization ---

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
