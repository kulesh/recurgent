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
      return history if history.is_a?(Array)

      warn "[AGENT HISTORY #{@role}] coercing malformed context[:conversation_history] to []" if @debug
      @context[:conversation_history] = []
    end

    def _conversation_history_records
      history = @context[:conversation_history]
      return [] unless history.is_a?(Array)

      history
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
      summary[:value_class] = outcome.value.class.name unless outcome.value.nil?
      summary
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
end
