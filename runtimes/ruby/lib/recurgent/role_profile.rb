# frozen_string_literal: true

class Agent
  # Agent::RoleProfile — normalized explicit role-coordination contract.
  class RoleProfile
    MODES = %w[coordination prescriptive].freeze
    KINDS = %w[shared_state_slot return_shape_family signature_family].freeze

    class << self
      def normalize(profile, expected_role: nil)
        data = _deep_symbolize(profile)
        raise ArgumentError, "role_profile must be a Hash" unless data.is_a?(Hash)

        role = data[:role].to_s.strip
        raise ArgumentError, "role_profile[:role] must be provided" if role.empty?
        if expected_role && role != expected_role.to_s
          raise ArgumentError, "role_profile[:role] must match agent role '#{expected_role}'"
        end

        version = Integer(data[:version])
        raise ArgumentError, "role_profile[:version] must be >= 1" if version <= 0

        constraints = data[:constraints]
        raise ArgumentError, "role_profile[:constraints] must be a Hash" unless constraints.is_a?(Hash)

        normalized_constraints = constraints.each_with_object({}) do |(name, raw_constraint), memo|
          memo[name.to_sym] = _normalize_constraint(name: name, constraint: raw_constraint)
        end

        {
          role: role,
          version: version,
          constraints: normalized_constraints
        }
      end

      private

      def _normalize_constraint(name:, constraint:)
        raw = _deep_symbolize(constraint)
        raise ArgumentError, "role_profile constraint '#{name}' must be a Hash" unless raw.is_a?(Hash)

        kind = raw[:kind].to_s.strip
        kind = "shared_state_slot" if kind.empty?
        raise ArgumentError, "role_profile constraint '#{name}' has unsupported kind '#{kind}'" unless KINDS.include?(kind)

        mode = raw[:mode].to_s.strip
        mode = "coordination" if mode.empty?
        raise ArgumentError, "role_profile constraint '#{name}' has unsupported mode '#{mode}'" unless MODES.include?(mode)

        methods = Array(raw[:methods]).map { |entry| entry.to_s.strip }.reject(&:empty?).uniq
        raise ArgumentError, "role_profile constraint '#{name}' requires at least one method" if methods.empty?

        normalized = {
          kind: kind.to_sym,
          methods: methods,
          mode: mode.to_sym
        }

        canonical_key = raw[:canonical_key]
        canonical_value = raw[:canonical_value]
        normalized[:canonical_key] = canonical_key.to_sym unless canonical_key.nil?
        normalized[:canonical_value] = canonical_value unless canonical_value.nil?

        if normalized[:mode] == :prescriptive &&
           normalized[:canonical_key].nil? &&
           normalized[:canonical_value].nil?
          raise ArgumentError,
                "role_profile constraint '#{name}' in prescriptive mode requires canonical_key or canonical_value"
        end

        normalized
      end

      def _deep_symbolize(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, entry), memo|
            memo[key.to_sym] = _deep_symbolize(entry)
          end
        when Array
          value.map { |entry| _deep_symbolize(entry) }
        else
          value
        end
      end
    end
  end
end
