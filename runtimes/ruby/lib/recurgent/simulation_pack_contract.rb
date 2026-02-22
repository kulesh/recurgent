# frozen_string_literal: true

class Agent
  # Agent::SimulationPackContract validates machine-readable scenario packs
  # used by simulation readiness gates.
  class SimulationPackContract
    SCHEMA_VERSION = 1
    SCENARIO_CLASSES = %w[class_1 class_2_plus].freeze
    REQUIRED_WEIGHT_KEYS = %w[correctness contract_adherence repair_efficiency reuse].freeze

    def self.validate!(raw_pack, source_path: nil)
      pack = _normalize_pack(raw_pack)
      _validate_core_fields!(pack, source_path: source_path)
      _validate_replay!(pack.fetch("replay"), source_path: source_path)
      _validate_scoring_profile!(pack.fetch("scoring_profile"), source_path: source_path)
      _validate_oracles!(pack.fetch("oracles"), source_path: source_path)
      pack
    end

    class << self
      private

      def _normalize_pack(raw_pack)
        raise ArgumentError, "scenario pack must be a Hash" unless raw_pack.is_a?(Hash)

        raw_pack.transform_keys(&:to_s)
      end

      def _validate_core_fields!(pack, source_path:)
        _assert_required_fields!(pack, %w[version id class scoring_profile replay oracles], source_path: source_path)
        _assert(pack["version"].to_i == SCHEMA_VERSION, "version must equal #{SCHEMA_VERSION}", source_path: source_path)
        _fetch_non_empty_string!(pack, "id", source_path: source_path)
        _assert(SCENARIO_CLASSES.include?(pack["class"].to_s), "class must be one of: #{SCENARIO_CLASSES.join(", ")}",
                source_path: source_path)
      end

      def _validate_replay!(replay, source_path:)
        replay_hash = _fetch_hash!(replay, "replay", source_path: source_path)
        mode = _fetch_mode!(replay_hash, source_path: source_path)
        _assert(%w[fixture replay live].include?(mode), "replay.mode must be fixture|replay|live",
                source_path: source_path)
        _fetch_unique_integer_array!(replay_hash, "seeds", source_path: source_path)
      end

      def _validate_scoring_profile!(scoring_profile, source_path:)
        profile_hash = _fetch_hash!(scoring_profile, "scoring_profile", source_path: source_path)
        _fetch_non_empty_string!(profile_hash, "id", source_path: source_path)
        weights = _fetch_hash!(profile_hash["weights"] || profile_hash[:weights], "scoring_profile.weights",
                               source_path: source_path)
        normalized_weights = weights.transform_keys(&:to_s).transform_values(&:to_f)
        _assert_required_fields!(normalized_weights, REQUIRED_WEIGHT_KEYS, source_path: source_path)
        _assert(normalized_weights.values.all? { |weight| weight >= 0.0 }, "all scoring weights must be >= 0",
                source_path: source_path)
        total = normalized_weights.values.sum.round(6)
        _assert((total - 1.0).abs <= 0.000_001, "scoring weights must sum to 1.0 (got #{total})",
                source_path: source_path)
      end

      def _validate_oracles!(oracles, source_path:)
        _assert(oracles.is_a?(Array) && !oracles.empty?, "oracles must be a non-empty Array", source_path: source_path)
        ids = oracles.map { |oracle| _validate_oracle!(oracle, source_path: source_path) }
        _assert(ids.uniq.length == ids.length, "oracle ids must be unique", source_path: source_path)
      end

      def _error_message(message, source_path:)
        return message if source_path.to_s.strip.empty?

        "#{source_path}: #{message}"
      end

      def _assert(condition, message, source_path:)
        return if condition

        raise ArgumentError, _error_message(message, source_path: source_path)
      end

      def _assert_required_fields!(payload, required_fields, source_path:)
        missing = required_fields.reject { |field| payload.key?(field) }
        _assert(missing.empty?, "missing required fields: #{missing.join(", ")}", source_path: source_path)
      end

      def _fetch_hash!(value, name, source_path:)
        _assert(value.is_a?(Hash), "#{name} must be a Hash", source_path: source_path)
        value
      end

      def _fetch_non_empty_string!(payload, key, source_path:)
        value = payload[key] || payload[key.to_sym]
        _assert(value.to_s.strip != "", "#{key} must be a non-empty string", source_path: source_path)
        value.to_s
      end

      def _fetch_mode!(replay_hash, source_path:)
        _fetch_non_empty_string!(replay_hash, "mode", source_path: source_path)
      end

      def _fetch_unique_integer_array!(payload, key, source_path:)
        value = payload[key] || payload[key.to_sym]
        _assert(value.is_a?(Array) && !value.empty?, "#{key} must be a non-empty integer array", source_path: source_path)
        _assert(value.all? { |entry| entry.is_a?(Integer) }, "#{key} must contain integers only", source_path: source_path)
        _assert(value.uniq.length == value.length, "#{key} must be unique", source_path: source_path)
        value
      end

      def _validate_oracle!(oracle, source_path:)
        oracle_hash = _fetch_hash!(oracle, "oracle entry", source_path: source_path)
        oracle_id = _fetch_non_empty_string!(oracle_hash, "id", source_path: source_path)
        _fetch_non_empty_string!(oracle_hash, "kind", source_path: source_path)
        _fetch_hash!(oracle_hash["input"] || oracle_hash[:input], "oracle '#{oracle_id}' input", source_path: source_path)
        _fetch_hash!(oracle_hash["expect"] || oracle_hash[:expect], "oracle '#{oracle_id}' expect", source_path: source_path)
        oracle_id
      end
    end
  end
end
