# frozen_string_literal: true

class Agent
  # Agent::OutcomeContractConstraints — machine-checkable utility constraint helpers.
  module OutcomeContractConstraints
    private

    def _validate_object_constraints(deliverable:, value:)
      properties = _contract_constraint_properties(deliverable)
      return _valid_contract_validation(value) if properties.empty?

      properties.each do |property_name, property_constraints|
        key = property_name.to_s
        next unless _tolerant_hash_key?(value, key)

        property_value = _tolerant_hash_value(value, key)
        type_violation = _validate_property_constraint_type(key, property_value, property_constraints)
        return type_violation unless type_violation.nil?

        min_items_violation = _validate_property_min_items_constraint(key, property_value, property_constraints)
        return min_items_violation unless min_items_violation.nil?
      end

      _valid_contract_validation(value)
    end

    def _validate_property_constraint_type(key, property_value, property_constraints)
      expected_type = _constraint_type(property_constraints)
      return nil if expected_type.nil?
      return nil if expected_type == "array" && property_value.is_a?(Array)

      _invalid_contract_validation(
        mismatch: "property_type_mismatch",
        expected_shape: expected_type,
        actual_shape: _value_shape(property_value),
        expected_keys: [key],
        actual_keys: [],
        details: { constraint_path: "deliverable.constraints.properties.#{key}.type" }
      )
    end

    def _validate_property_min_items_constraint(key, property_value, property_constraints)
      min_items = _constraint_min_items(property_constraints)
      return nil if min_items.nil?
      return nil if property_value.is_a?(Array) && property_value.length >= min_items

      actual_items = property_value.is_a?(Array) ? property_value.length : nil
      _invalid_contract_validation(
        mismatch: "min_items_violation",
        expected_shape: "array",
        actual_shape: _value_shape(property_value),
        expected_keys: [key],
        actual_keys: [],
        details: {
          constraint_path: "deliverable.constraints.properties.#{key}.min_items",
          expected_min_items: min_items,
          actual_items: actual_items
        }
      )
    end

    def _deliverable_min_items(deliverable)
      top_level = _constraint_min_items(deliverable)
      return top_level unless top_level.nil?

      constraints = _contract_constraints(deliverable)
      _constraint_min_items(constraints)
    end

    def _contract_constraint_properties(deliverable)
      constraints = _contract_constraints(deliverable)
      properties = constraints[:properties] || constraints["properties"]
      return {} unless properties.is_a?(Hash)

      properties
    end

    def _contract_constraints(deliverable)
      constraints = deliverable[:constraints] || deliverable["constraints"]
      return {} unless constraints.is_a?(Hash)

      constraints
    end

    def _constraint_type(constraint)
      raw = constraint[:type] || constraint["type"]
      return nil if raw.nil?

      raw.to_s.strip.downcase
    end

    def _constraint_min_items(constraint)
      raw = constraint[:min_items] || constraint["min_items"]
      return nil if raw.nil?

      min_items = raw.is_a?(Integer) ? raw : Integer(raw, 10)
      return nil if min_items.negative?

      min_items
    rescue ArgumentError, TypeError
      nil
    end

    def _tolerant_hash_value(hash_value, key)
      key_str = key.to_s
      return hash_value[key_str] if hash_value.key?(key_str)

      hash_value[key_str.to_sym]
    end
  end
end
