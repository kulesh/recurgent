# frozen_string_literal: true

class Agent
  # Agent::OutcomeContractValidator — delegated success boundary contract checks with tolerant key semantics.
  module OutcomeContractValidator
    include OutcomeContractShapes

    private

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
  end
end
