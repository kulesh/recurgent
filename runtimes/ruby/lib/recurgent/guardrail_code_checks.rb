# frozen_string_literal: true

class Agent
  # Agent::GuardrailCodeChecks — generated-code pattern checks used by guardrail policy.
  module GuardrailCodeChecks
    EXTERNAL_RETRIEVAL_MODES = %w[live cached fixture].freeze

    private

    def _context_tools_shape_misuse?(source)
      match = source.match(/context\[:tools\].*?\{\s*\|([a-zA-Z_]\w*)\|/m)
      return false unless match

      item_var = match[1]
      source.match?(/\b#{Regexp.escape(item_var)}\s*\[\s*(?::name|["']name["'])\s*\]/)
    end

    def _hardcoded_external_fallback_success?(source)
      normalized_source = _source_without_ruby_comments(source)
      fetch_like = normalized_source.match?(%r{Net::HTTP|net/http|tool\(["']web_fetcher["']\)|fetch_result}i)
      return false unless fetch_like

      fallback_var = normalized_source.match(/\b(fallback_[a-zA-Z_]\w*)\s*=\s*\[/)&.captures&.first
      return false if fallback_var.nil?

      normalized_source.match?(/\bOutcome\.ok\(\s*#{Regexp.escape(fallback_var)}\s*\)/)
    end

    def _missing_external_provenance_success?(source, outcome)
      return false unless outcome.is_a?(Outcome) && outcome.ok?
      return false unless _external_data_flow_source?(source)

      !_outcome_value_has_external_provenance?(outcome.value)
    end

    def _validate_generated_code_policy!(_method_name, code)
      source = code.to_s
      if source.match?(/\.\s*define_singleton_method\s*\(/)
        raise ToolRegistryViolationError,
              "Defining singleton methods on Agent instances is not supported; use tool/delegate invocation paths."
      end

      if _context_tools_shape_misuse?(source)
        raise ToolRegistryViolationError,
              "context[:tools] is a Hash keyed by tool name; use key? or iterate |tool_name, metadata| " \
              "(not |t| with t[:name])."
      end

      return unless _hardcoded_external_fallback_success?(source)

      raise ToolRegistryViolationError,
            "Hardcoded fallback payloads for external-fetch flows must not return Outcome.ok; " \
            "emit low_utility/unsupported_capability instead."
    end

    def _validate_generated_outcome_policy!(_method_name, code, outcome)
      source = code.to_s
      return unless _missing_external_provenance_success?(source, outcome)

      raise ToolRegistryViolationError,
            "External-data success must include `provenance.sources[]` with " \
            "`uri`, `fetched_at`, `retrieval_tool`, and `retrieval_mode` (`live|cached|fixture`)."
    end

    def _external_data_flow_source?(source)
      normalized_source = _source_without_ruby_comments(source)
      normalized_source.match?(%r{
        tool\(\s*["'][\w-]*fetch[\w-]*["']\s*\)|
        delegate\(\s*["'][\w-]*fetch[\w-]*["']\s*[,)]|
        require\s*["']net/http["']|
        \bNet::HTTP\b
      }ix)
    end

    def _outcome_value_has_external_provenance?(value)
      return false unless value.is_a?(Hash)

      provenance = _guardrail_hash_value(value, :provenance)
      return false unless provenance.is_a?(Hash)

      sources = _guardrail_hash_value(provenance, :sources)
      return false unless sources.is_a?(Array) && !sources.empty?

      sources.all? { |source_entry| _valid_provenance_source_entry?(source_entry) }
    end

    def _valid_provenance_source_entry?(source_entry)
      return false unless source_entry.is_a?(Hash)
      return false unless _provenance_source_required_fields_present?(source_entry)

      EXTERNAL_RETRIEVAL_MODES.include?(_provenance_source_retrieval_mode(source_entry))
    end

    def _provenance_source_required_fields_present?(source_entry)
      required_fields = %i[uri fetched_at retrieval_tool]
      required_fields.all? do |field|
        !_guardrail_blank?(_guardrail_hash_value(source_entry, field))
      end
    end

    def _provenance_source_retrieval_mode(source_entry)
      mode = _guardrail_hash_value(source_entry, :retrieval_mode)
      return nil if mode.nil?

      mode.to_s.strip.downcase
    end

    def _guardrail_hash_value(hash_value, key)
      hash_value[key] || hash_value[key.to_s]
    end

    def _guardrail_blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def _source_without_ruby_comments(source)
      source.each_line.map { |line| line.sub(/#.*$/, "") }.join("\n")
    end
  end
end
