# frozen_string_literal: true

class Agent
  # Agent::RoleProfileGuard — continuity checks for opt-in role profiles.
  module RoleProfileGuard
    private

    def _evaluate_role_profile_continuity!(profile:, method_name:, code:, outcome:, state:)
      _reset_role_profile_compliance_state!(state)
      return outcome if profile.nil?

      state.role_profile_shadow_mode = _role_profile_shadow_mode_enabled?
      state.role_profile_enforced = _role_profile_enforcement_enabled?
      report = _role_profile_continuity_report(profile: profile, method_name: method_name, code: code, outcome: outcome)

      state.role_profile_compliance = report
      state.role_profile_violation_count = report[:violation_count]
      state.role_profile_violation_types = report[:violation_types]
      state.role_profile_correction_hint = report[:correction_hint]

      return outcome if report[:passed] || !state.role_profile_enforced

      raise ToolRegistryViolationError,
            "role_profile_continuity_violation: #{report[:reason]}. correction: #{report[:correction_hint]}"
    end

    def _role_profile_shadow_mode_enabled?
      @runtime_config.fetch(:role_profile_shadow_mode_enabled, true) == true
    end

    def _role_profile_enforcement_enabled?
      @runtime_config.fetch(:role_profile_enforcement_enabled, false) == true
    end

    def _role_profile_continuity_report(profile:, method_name:, code:, outcome:)
      constraints = _role_profile_constraints_for_method(profile: profile, method_name: method_name)
      return _role_profile_empty_report(profile: profile) if constraints.empty?

      results = constraints.map do |constraint_name, constraint|
        _role_profile_evaluate_constraint(
          constraint_name: constraint_name,
          constraint: constraint,
          method_name: method_name,
          code: code,
          outcome: outcome
        )
      end

      total = results.length
      failed = results.reject { |entry| entry[:passed] }
      pass_rate = total.zero? ? 1.0 : ((total - failed.length).to_f / total).round(4)
      correction_hint = failed.first&.dig(:correction_hint)
      {
        profile_version: profile[:version],
        evaluated: true,
        continuity_pass_rate: pass_rate,
        passed: failed.empty?,
        violation_count: failed.length,
        violation_types: failed.map { |entry| entry[:type] },
        correction_hint: correction_hint,
        reason: failed.first&.dig(:reason),
        constraint_results: results
      }
    end

    def _role_profile_empty_report(profile:)
      {
        profile_version: profile[:version],
        evaluated: false,
        continuity_pass_rate: 1.0,
        passed: true,
        violation_count: 0,
        violation_types: [],
        correction_hint: nil,
        reason: nil,
        constraint_results: []
      }
    end

    def _role_profile_constraints_for_method(profile:, method_name:)
      constraints = profile[:constraints]
      return [] unless constraints.is_a?(Hash)

      method = method_name.to_s
      constraints.select do |_name, constraint|
        _role_profile_constraint_applies_to_method?(constraint: constraint, method_name: method)
      end
    end

    def _role_profile_evaluate_constraint(constraint_name:, constraint:, method_name:, code:, outcome:)
      kind = constraint[:kind].to_sym
      scoped_methods = _role_profile_constraint_methods(constraint: constraint, method_name: method_name, kind: kind)
      observations, family_label = _role_profile_constraint_observations(
        kind: kind,
        constraint: constraint,
        scoped_methods: scoped_methods,
        method_name: method_name,
        code: code,
        outcome: outcome
      )
      passed = _role_profile_constraint_pass?(constraint: constraint, observations: observations)
      result = {
        constraint: constraint_name.to_s,
        kind: kind.to_s,
        mode: constraint[:mode].to_s,
        scope: constraint[:scope].to_s,
        methods: scoped_methods,
        observations: observations,
        family_label: family_label,
        passed: passed,
        type: "#{kind}_drift"
      }
      return result if passed

      expected = _role_profile_constraint_expected_value(constraint)
      result[:reason] = if expected
                          "#{family_label} diverged from expected value '#{expected}'"
                        else
                          "#{family_label} diverged across sibling methods"
                        end
      result[:correction_hint] = _role_profile_constraint_correction_hint(
        constraint: constraint,
        expected: expected,
        observations: observations
      )
      result
    end

    def _role_profile_constraint_observations(kind:, constraint:, scoped_methods:, method_name:, code:, outcome:)
      case kind
      when :shared_state_slot
        [
          _role_profile_shared_state_observations(
            method_names: scoped_methods,
            method_name: method_name,
            code: code
          ),
          "state key"
        ]
      when :return_shape_family
        [
          _role_profile_return_shape_observations(
            method_names: scoped_methods,
            method_name: method_name,
            outcome: outcome
          ),
          "return shape"
        ]
      when :signature_family
        [
          _role_profile_signature_observations(
            method_names: scoped_methods,
            method_name: method_name,
            code: code
          ),
          "method signature"
        ]
      else
        [[], "constraint value"]
      end
    end

    def _role_profile_shared_state_observations(method_names:, method_name:, code:)
      metadata = _toolstore_load_registry_tools[@role.to_s]
      method_profiles = _toolstore_method_state_key_profiles(metadata || {}).transform_values do |keys|
        Array(keys).map(&:to_s).reject(&:empty?).sort.first
      end
      method_profiles.merge!(_role_profile_cached_observations(kind: :shared_state_slot))
      current_keys = _toolstore_state_keys_from_code(code.to_s).map(&:to_s).reject(&:empty?).uniq
      current_primary = current_keys.sort.first
      if current_primary
        method_profiles[method_name.to_s] = current_primary
        _role_profile_record_observation(kind: :shared_state_slot, method_name: method_name, value: current_primary)
      end

      Array(method_names).filter_map do |name|
        method = name.to_s
        next current_primary if method == method_name.to_s && current_primary

        artifact_key = _role_profile_artifact_primary_state_key(method)
        unless artifact_key.nil?
          _role_profile_record_observation(kind: :shared_state_slot, method_name: method, value: artifact_key)
          next artifact_key
        end

        method_profiles[method].to_s.strip.then { |value| value.empty? ? nil : value }
      end
    end

    def _role_profile_artifact_primary_state_key(method_name)
      artifact = _artifact_load(method_name)
      return nil unless artifact.is_a?(Hash)

      scorecard = _artifact_scorecard_for(artifact)
      return nil unless scorecard.is_a?(Hash)

      latest = Array(scorecard["state_key_observations"]).last
      Array(latest).map(&:to_s).reject(&:empty?).sort.first
    end

    def _role_profile_return_shape_observations(method_names:, method_name:, outcome:)
      metadata = _toolstore_load_registry_tools[@role.to_s]
      shape_profiles = _role_profile_method_return_shapes(metadata || {})
      shape_profiles.merge!(_role_profile_cached_observations(kind: :return_shape_family))
      current_shape = _role_profile_value_shape(outcome.value)
      unless current_shape.nil?
        shape_profiles[method_name.to_s] = current_shape
        _role_profile_record_observation(kind: :return_shape_family, method_name: method_name, value: current_shape)
      end

      Array(method_names).filter_map { |name| shape_profiles[name.to_s] }
    end

    def _role_profile_signature_observations(method_names:, method_name:, code:)
      metadata = _toolstore_load_registry_tools[@role.to_s]
      signature_profiles = _role_profile_method_signatures(metadata || {})
      signature_profiles.merge!(_role_profile_cached_observations(kind: :signature_family))
      current_signature = _role_profile_signature_from_code(code.to_s)
      unless current_signature.to_s.empty?
        signature_profiles[method_name.to_s] = current_signature
        _role_profile_record_observation(kind: :signature_family, method_name: method_name, value: current_signature)
      end

      Array(method_names).filter_map { |name| signature_profiles[name.to_s] }
    end

    def _role_profile_constraint_applies_to_method?(constraint:, method_name:)
      case constraint[:scope].to_sym
      when :all_methods
        !Array(constraint[:exclude_methods]).map(&:to_s).include?(method_name.to_s)
      when :explicit_methods
        Array(constraint[:methods]).map(&:to_s).include?(method_name.to_s)
      else
        false
      end
    end

    def _role_profile_constraint_methods(constraint:, method_name:, kind:)
      case constraint[:scope].to_sym
      when :explicit_methods
        Array(constraint[:methods]).map(&:to_s).reject(&:empty?).uniq
      when :all_methods
        methods = _role_profile_observed_methods(kind: kind)
        methods << method_name.to_s
        excluded = Array(constraint[:exclude_methods]).map(&:to_s).reject(&:empty?)
        methods.reject { |name| excluded.include?(name) }.uniq
      else
        [method_name.to_s]
      end
    end

    def _role_profile_observed_methods(kind:)
      metadata = _toolstore_load_registry_tools[@role.to_s] || {}
      method_names = _toolstore_method_names(metadata)
      kind_profiles = case kind
                      when :shared_state_slot
                        _toolstore_method_state_key_profiles(metadata).keys
                      when :return_shape_family
                        _role_profile_method_return_shapes(metadata).keys
                      when :signature_family
                        _role_profile_method_signatures(metadata).keys
                      else
                        []
                      end
      cached_methods = _role_profile_cached_observations(kind: kind).keys
      (method_names + kind_profiles + cached_methods).map(&:to_s).reject(&:empty?).uniq
    end

    def _role_profile_cached_observations(kind:)
      cache = (@role_profile_observation_cache ||= {})
      scoped = cache[kind.to_sym]
      return {} unless scoped.is_a?(Hash)

      scoped.transform_keys(&:to_s)
    end

    def _role_profile_record_observation(kind:, method_name:, value:)
      normalized_method = method_name.to_s.strip
      normalized_value = value.to_s.strip
      return if normalized_method.empty? || normalized_value.empty?

      @role_profile_observation_cache ||= {}
      @role_profile_observation_cache[kind.to_sym] ||= {}
      @role_profile_observation_cache[kind.to_sym][normalized_method] = normalized_value
    end

    def _role_profile_method_return_shapes(metadata)
      return {} unless metadata.is_a?(Hash)

      raw = metadata[:method_return_shapes] || metadata["method_return_shapes"]
      return {} unless raw.is_a?(Hash)

      raw.each_with_object({}) do |(method_name, shape), memo|
        normalized = shape.to_s.strip
        memo[method_name.to_s] = normalized unless normalized.empty?
      end
    end

    def _role_profile_method_signatures(metadata)
      return {} unless metadata.is_a?(Hash)

      raw = metadata[:method_signatures] || metadata["method_signatures"]
      return {} unless raw.is_a?(Hash)

      raw.each_with_object({}) do |(method_name, signature), memo|
        normalized = signature.to_s.strip
        memo[method_name.to_s] = normalized unless normalized.empty?
      end
    end

    def _role_profile_signature_from_code(code)
      arg_indexes = code.scan(/args\[(\d+)\]/).flatten.map(&:to_i).uniq.sort
      kw_keys = code.scan(/kwargs\[(?::|["'])([a-zA-Z0-9_]+)["']?\]/).flatten.map(&:to_s).uniq.sort

      args_part = arg_indexes.empty? ? "none" : arg_indexes.join(",")
      kwargs_part = kw_keys.empty? ? "none" : kw_keys.join(",")
      "args:#{args_part}|kwargs:#{kwargs_part}"
    end

    def _role_profile_value_shape(value)
      case value
      when Hash
        "hash:#{value.keys.map(&:to_s).sort.join(",")}"
      when Array
        "array"
      when Numeric
        "numeric"
      when String
        "string"
      when NilClass
        "nil"
      else
        value.class.name.to_s
      end
    end

    def _role_profile_constraint_pass?(constraint:, observations:)
      return true if observations.empty?

      mode = constraint[:mode].to_sym
      case mode
      when :coordination
        observations.uniq.length == 1
      when :prescriptive
        expected = _role_profile_constraint_expected_value(constraint)
        observations.all? { |value| value.to_s == expected.to_s }
      else
        true
      end
    end

    def _role_profile_constraint_expected_value(constraint)
      return constraint[:canonical_key].to_s if constraint.key?(:canonical_key)
      return constraint[:canonical_value].to_s if constraint.key?(:canonical_value)

      nil
    end

    def _role_profile_constraint_correction_hint(constraint:, expected:, observations:)
      if expected
        "Use '#{expected}' consistently for this profile constraint."
      else
        target = observations.tally.max_by { |_value, count| count }&.first
        return "Align sibling methods to one shared value for this constraint." if target.nil?

        "Align sibling methods to '#{target}' for this profile constraint."
      end
    end

    def _reset_role_profile_compliance_state!(state)
      state.role_profile_compliance = nil
      state.role_profile_violation_count = 0
      state.role_profile_violation_types = []
      state.role_profile_correction_hint = nil
      state.role_profile_shadow_mode = false
      state.role_profile_enforced = false
    end
  end
end
