# frozen_string_literal: true

class Agent
  # Agent::OutcomeContractShapes — deliverable type/shape validation helpers.
  module OutcomeContractShapes
    include OutcomeContractConstraints

    private

    def _contract_type(deliverable)
      raw = deliverable[:type] || deliverable["type"]
      return nil if raw.nil?

      raw.to_s.strip.downcase
    end

    def _validate_object_deliverable(deliverable:, value:)
      expected_keys = _required_contract_keys(deliverable)
      unless value.is_a?(Hash)
        return _invalid_contract_validation(
          mismatch: "type_mismatch",
          expected_shape: "object",
          actual_shape: _value_shape(value),
          expected_keys: expected_keys,
          actual_keys: _actual_key_descriptors(value)
        )
      end

      missing = expected_keys.reject { |key| _tolerant_hash_key?(value, key) }
      if missing.any?
        return _invalid_contract_validation(
          mismatch: "missing_required_key",
          expected_shape: "object",
          actual_shape: "object",
          expected_keys: expected_keys,
          actual_keys: _actual_key_descriptors(value)
        )
      end

      normalized = _with_tolerant_key_aliases(value)
      constraints_validation = _validate_object_constraints(deliverable: deliverable, value: normalized)
      return constraints_validation unless constraints_validation[:valid]

      _valid_contract_validation(normalized)
    end

    def _validate_array_deliverable(deliverable:, value:)
      unless value.is_a?(Array)
        return _invalid_contract_validation(
          mismatch: "type_mismatch",
          expected_shape: "array",
          actual_shape: _value_shape(value),
          expected_keys: [],
          actual_keys: _actual_key_descriptors(value)
        )
      end

      min_items = _deliverable_min_items(deliverable)
      if min_items && value.length < min_items
        return _invalid_contract_validation(
          mismatch: "min_items_violation",
          expected_shape: "array",
          actual_shape: "array",
          expected_keys: [],
          actual_keys: [],
          details: {
            constraint_path: "deliverable.min_items",
            expected_min_items: min_items,
            actual_items: value.length
          }
        )
      end

      _valid_contract_validation(value)
    end

    def _required_contract_keys(deliverable)
      Array(deliverable[:required] || deliverable["required"]).map(&:to_s).reject(&:empty?).uniq
    end

    def _tolerant_hash_key?(hash_value, key)
      key_str = key.to_s
      hash_value.key?(key_str) || hash_value.key?(key_str.to_sym)
    end

    def _with_tolerant_key_aliases(hash_value)
      normalized = hash_value.dup
      hash_value.each do |key, entry_value|
        if key.is_a?(Symbol)
          normalized[key.to_s] = entry_value unless normalized.key?(key.to_s)
        elsif key.is_a?(String)
          symbol_key = key.to_sym
          normalized[symbol_key] = entry_value unless normalized.key?(symbol_key)
        end
      end
      normalized
    end

    def _actual_key_descriptors(value)
      return [] unless value.is_a?(Hash)

      value.keys.map { |key| key.is_a?(Symbol) ? ":#{key}" : key.to_s }.uniq
    end

    def _value_shape(value)
      return "object" if value.is_a?(Hash)
      return "array" if value.is_a?(Array)
      return "null" if value.nil?

      value.class.name.to_s.downcase
    end

    def _valid_contract_validation(normalized_value)
      {
        valid: true,
        normalized_value: normalized_value,
        metadata: {}
      }
    end

    def _invalid_contract_validation(mismatch:, expected_shape:, actual_shape:, expected_keys:, actual_keys:, details: {})
      metadata = {
        expected_shape: expected_shape,
        actual_shape: actual_shape,
        expected_keys: expected_keys,
        actual_keys: actual_keys,
        mismatch: mismatch
      }
      metadata.merge!(details) if details.is_a?(Hash) && !details.empty?

      {
        valid: false,
        normalized_value: nil,
        metadata: metadata
      }
    end
  end
end
