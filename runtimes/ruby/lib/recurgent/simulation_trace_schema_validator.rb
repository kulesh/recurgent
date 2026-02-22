# frozen_string_literal: true

require "json"

class Agent
  # Agent::SimulationTraceSchemaValidator validates JSONL traces against required log-entry shape.
  class SimulationTraceSchemaValidator
    def initialize(entry_schema_path: _default_entry_schema_path)
      @entry_schema_path = entry_schema_path.to_s
      @entry_schema = JSON.parse(File.read(@entry_schema_path))
      @required_fields = Array(@entry_schema["required"]).map(&:to_s)
      @properties = @entry_schema.fetch("properties", {})
    end

    def validate(log_path:)
      return _skip_result("trace_log_missing") if log_path.to_s.strip.empty?
      return _skip_result("trace_log_not_found") unless File.exist?(log_path)

      entry_count = 0
      File.foreach(log_path).with_index do |line, index|
        next if line.to_s.strip.empty?

        entry_count += 1
        json = JSON.parse(line)
        invalid = _validate_entry(json)
        next if invalid.nil?

        return _invalid_result(
          entry_index: index,
          field_path: invalid[:field_path],
          reason: invalid[:reason],
          entry_count: entry_count
        )
      rescue JSON::ParserError => e
        return _invalid_result(
          entry_index: index,
          field_path: "$[#{index}]",
          reason: "invalid_json: #{e.message}",
          entry_count: entry_count
        )
      end

      {
        "valid" => true,
        "entry_count" => entry_count
      }
    end

    private

    def _validate_entry(entry)
      return _invalid("$", "entry must be a JSON object") unless entry.is_a?(Hash)

      missing = @required_fields.reject { |field| entry.key?(field) }
      return _invalid("$", "missing required fields: #{missing.join(", ")}") unless missing.empty?

      _validate_typed_field(entry, "duration_ms", Numeric) ||
        _validate_typed_field(entry, "generation_attempt", Integer) ||
        _validate_enum_field(entry, "outcome_status") ||
        nil
    end

    def _validate_typed_field(entry, field, ruby_class)
      return nil unless entry.key?(field)
      return nil if entry[field].nil? || entry[field].is_a?(ruby_class)

      _invalid("$.#{field}", "expected #{ruby_class}, got #{entry[field].class}")
    end

    def _validate_enum_field(entry, field)
      return nil unless entry.key?(field)

      allowed_values = Array(@properties.dig(field, "enum"))
      return nil if allowed_values.empty?
      return nil if entry[field].nil? || allowed_values.include?(entry[field])

      _invalid("$.#{field}", "expected one of #{allowed_values.inspect}, got #{entry[field].inspect}")
    end

    def _invalid(field_path, reason)
      { field_path: field_path, reason: reason }
    end

    def _skip_result(reason)
      {
        "valid" => nil,
        "entry_count" => 0,
        "skipped_reason" => reason
      }
    end

    def _invalid_result(entry_index:, field_path:, reason:, entry_count:)
      {
        "valid" => false,
        "entry_count" => entry_count,
        "first_invalid_entry_index" => entry_index,
        "first_invalid_field_path" => field_path,
        "first_invalid_reason" => reason
      }
    end

    def _default_entry_schema_path
      File.expand_path("../../../../specs/contract/v1/recurgent-log-entry.schema.json", __dir__)
    end
  end
end
