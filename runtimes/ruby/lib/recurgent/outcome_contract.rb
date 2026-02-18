# frozen_string_literal: true

class Agent
  # Agent::OutcomeContractValidator — delegated success boundary contract checks with tolerant key semantics.
  #
  # Validates that delegated outcomes satisfy their deliverable contracts. Covers type/shape
  # matching, required-key enforcement, tolerant key normalization, and machine-checkable
  # property constraints (type + min_items).
  module OutcomeContractValidator
    private

    # -- Top-level contract validation ------------------------------------------

    def _validate_delegated_outcome_contract(outcome:, method_name:, args:, kwargs:, state:)
      _reset_contract_validation_state!(state)
      deliverable = _delegation_deliverable_contract
      return outcome unless _contract_validation_applicable?(outcome: outcome, deliverable: deliverable)

      validation = _validate_contract_payload(
        deliverable: deliverable,
        value: outcome.value,
        args: args,
        kwargs: kwargs
      )
      _capture_contract_validation_state!(state, validation)
      return _validated_success_outcome(outcome, validation) if validation[:valid]

      _contract_violation_outcome(method_name: method_name, validation: validation)
    end

    def _contract_validation_applicable?(outcome:, deliverable:)
      outcome.ok? && deliverable.is_a?(Hash)
    end

    def _delegation_deliverable_contract
      return nil unless @delegation_contract.is_a?(Hash)

      @delegation_contract[:deliverable] || @delegation_contract["deliverable"]
    end

    def _validate_contract_payload(deliverable:, value:, args:, kwargs:)
      nil_input_validation = _validate_nil_required_input(args: args, kwargs: kwargs, value: value)
      return nil_input_validation unless nil_input_validation.nil?

      expected_type = _contract_type(deliverable)
      return _valid_contract_validation(value) if expected_type.nil?
      return _validate_object_deliverable(deliverable: deliverable, value: value) if expected_type == "object"
      return _validate_array_deliverable(deliverable: deliverable, value: value) if expected_type == "array"

      _valid_contract_validation(value)
    end

    def _validate_nil_required_input(args:, kwargs:, value:)
      return nil unless _nil_required_input?(args: args, kwargs: kwargs)
      return nil unless _empty_success_value?(value)

      _invalid_contract_validation(
        mismatch: "nil_required_input",
        expected_shape: "non_nil_input",
        actual_shape: "nil",
        expected_keys: [],
        actual_keys: []
      )
    end

    def _nil_required_input?(args:, kwargs:)
      !args.empty? && args.first.nil? && kwargs.empty?
    end

    def _empty_success_value?(value)
      (value.is_a?(Array) && value.empty?) || (value.is_a?(Hash) && value.empty?)
    end

    def _validated_success_outcome(outcome, validation)
      normalized_value = validation[:normalized_value]
      return outcome if normalized_value.equal?(outcome.value)
      return outcome if normalized_value == outcome.value

      Outcome.ok(
        value: normalized_value,
        tool_role: outcome.tool_role,
        method_name: outcome.method_name
      )
    end

    def _contract_violation_outcome(method_name:, validation:)
      metadata = validation[:metadata]
      mismatch = metadata[:mismatch] || "contract_violation"
      error_message = "Delegated outcome does not satisfy deliverable contract (#{mismatch})"
      Outcome.error(
        error_type: "contract_violation",
        error_message: error_message,
        retriable: false,
        tool_role: @role,
        method_name: method_name,
        metadata: metadata
      )
    end

    def _reset_contract_validation_state!(state)
      state.contract_validation_applied = false
      state.contract_validation_passed = nil
      state.contract_validation_mismatch = nil
      state.contract_validation_expected_keys = []
      state.contract_validation_actual_keys = []
    end

    def _capture_contract_validation_state!(state, validation)
      metadata = validation[:metadata] || {}
      state.contract_validation_applied = true
      state.contract_validation_passed = validation[:valid]
      state.contract_validation_mismatch = metadata[:mismatch]
      state.contract_validation_expected_keys = metadata[:expected_keys] || []
      state.contract_validation_actual_keys = metadata[:actual_keys] || []
    end

    # -- Deliverable type/shape validation --------------------------------------

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

    # -- Machine-checkable property constraints ---------------------------------

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
