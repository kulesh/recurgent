# frozen_string_literal: true

class Agent
  # Agent::JsonNormalization — UTF-8 and JSON-safe serialization helpers for logs/history.
  module JsonNormalization
    private

    def _json_safe(value)
      case value
      when String
        _normalize_utf8(value)
      when Array
        value.map { |item| _json_safe(item) }
      when Hash
        value.each_with_object({}) do |(key, item), normalized|
          normalized[_json_safe_hash_key(key)] = _json_safe(item)
        end
      else
        value
      end
    end

    def _normalize_utf8(value)
      normalized = value.dup
      normalized.force_encoding(Encoding::UTF_8)
      return normalized if normalized.valid_encoding?

      normalized.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
    end

    def _json_safe_hash_key(key)
      return _normalize_utf8(key) if key.is_a?(String)
      return key if key.is_a?(Symbol)

      key
    end
  end
end
