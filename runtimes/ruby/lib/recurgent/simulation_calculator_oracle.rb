# frozen_string_literal: true

require "strscan"

class Agent
  # Agent::SimulationCalculatorOracle evaluates deterministic calculator oracles.
  # rubocop:disable Metrics/ClassLength
  class SimulationCalculatorOracle
    ORACLE_HANDLERS = {
      "calculator_expression" => :_evaluate_expression_oracle,
      "calculator_error_case" => :_evaluate_error_oracle,
      "assistant_followup_case" => :_evaluate_assistant_followup_oracle,
      "provenance_envelope_case" => :_evaluate_provenance_envelope_oracle,
      "typed_error_boundary_case" => :_evaluate_typed_error_boundary_oracle,
      "debate_orchestration_case" => :_evaluate_debate_orchestration_oracle,
      "live_outcome_value" => :_evaluate_live_outcome_value_oracle,
      "live_outcome_error" => :_evaluate_live_outcome_error_oracle,
      "live_provenance_envelope" => :_evaluate_live_provenance_envelope_oracle,
      "live_continuity_ref_resolution" => :_evaluate_live_continuity_ref_resolution_oracle
    }.freeze

    def evaluate(oracle, context: nil)
      oracle_hash = oracle.transform_keys(&:to_s)
      handler = ORACLE_HANDLERS[oracle_hash.fetch("kind")]
      return _error_observation("unsupported_oracle_kind", "unsupported oracle kind: #{oracle_hash["kind"]}") unless handler

      send(handler, oracle_hash, context)
    end

    private

    def _evaluate_expression_oracle(oracle, _context = nil)
      expression = oracle.fetch("input").fetch("expression").to_s
      expected_result = oracle.fetch("expect").fetch("result").to_f
      tolerance = oracle.fetch("expect").fetch("tolerance", 0.0).to_f
      observed_value = _evaluate_expression(expression)
      delta = (observed_value - expected_result).abs
      {
        "status" => "ok",
        "value" => observed_value,
        "passed" => delta <= tolerance,
        "details" => {
          "delta" => delta.round(12),
          "tolerance" => tolerance
        }
      }
    rescue StandardError, SyntaxError => e
      _error_observation(_error_type_for_exception(e), e.message)
    end

    def _evaluate_error_oracle(oracle, _context = nil)
      expression = oracle.fetch("input").fetch("expression").to_s
      expected_error = oracle.fetch("expect").fetch("error_type").to_s
      _evaluate_expression(expression)
      _error_observation("expected_error_not_raised", "expected #{expected_error} but expression succeeded")
    rescue StandardError, SyntaxError => e
      observed_error = _error_type_for_exception(e)
      {
        "status" => "error",
        "error_type" => observed_error,
        "passed" => observed_error == expected_error,
        "details" => {
          "expected_error_type" => expected_error,
          "message" => e.message
        }
      }
    end

    def _evaluate_assistant_followup_oracle(oracle, _context = nil)
      input = oracle.fetch("input")
      expect = oracle.fetch("expect")
      followup_query, resolved_content_ref, history_refs = _assistant_followup_fields(input)
      requires_content_ref = expect.fetch("requires_content_ref", true)
      query_requires_ref = _assistant_query_requires_ref?(followup_query)
      must_resolve_ref = requires_content_ref && query_requires_ref
      has_resolution = _assistant_resolved_from_history?(resolved_content_ref, history_refs)

      {
        "status" => must_resolve_ref && !has_resolution ? "error" : "ok",
        "passed" => !must_resolve_ref || has_resolution,
        "details" => {
          "query_requires_content_ref" => query_requires_ref,
          "history_ref_count" => history_refs.length,
          "resolved_content_ref" => resolved_content_ref,
          "resolved_from_history" => has_resolution
        }
      }
    rescue StandardError => e
      _error_observation("assistant_followup_oracle_error", e.message)
    end

    def _evaluate_provenance_envelope_oracle(oracle, _context = nil)
      input = oracle.fetch("input")
      expect = oracle.fetch("expect")
      required_keys = Array(expect.fetch("required_source_keys", %w[uri fetched_at retrieval_tool retrieval_mode]))
      allowed_modes = Array(expect.fetch("allowed_retrieval_modes", %w[live cached fixture knowledge_base]))
      min_sources = expect.fetch("min_sources", 1).to_i

      sources = Array(input.dig("success_payload", "provenance", "sources"))
      missing_key_count, invalid_mode_count = _provenance_source_violations(
        sources: sources,
        required_keys: required_keys,
        allowed_modes: allowed_modes
      )

      passed = sources.length >= min_sources && missing_key_count.zero? && invalid_mode_count.zero?
      {
        "status" => passed ? "ok" : "error",
        "passed" => passed,
        "details" => {
          "source_count" => sources.length,
          "min_sources" => min_sources,
          "missing_key_count" => missing_key_count,
          "invalid_mode_count" => invalid_mode_count
        }
      }
    rescue StandardError => e
      _error_observation("provenance_oracle_error", e.message)
    end

    def _evaluate_typed_error_boundary_oracle(oracle, _context = nil)
      input = oracle.fetch("input")
      expect = oracle.fetch("expect")

      allowed_error_types = Array(expect.fetch("allowed_error_types", []))
      require_non_retriable = expect.fetch("require_non_retriable", false)

      outcome = input.fetch("outcome")
      status = outcome.fetch("status", "").to_s
      error_type = outcome.fetch("error_type", "").to_s
      retriable = outcome.fetch("retriable", false) == true

      passed = status == "error" &&
               allowed_error_types.include?(error_type) &&
               (!require_non_retriable || retriable == false)

      {
        "status" => passed ? "ok" : "error",
        "passed" => passed,
        "details" => {
          "status" => status,
          "error_type" => error_type,
          "retriable" => retriable,
          "allowed_error_types" => allowed_error_types
        }
      }
    rescue StandardError => e
      _error_observation("typed_error_boundary_oracle_error", e.message)
    end

    def _evaluate_debate_orchestration_oracle(oracle, _context = nil)
      input = oracle.fetch("input")
      expect = oracle.fetch("expect")

      contributions = Array(input.fetch("contributions", []))
      panelists, rounds = _debate_panelists_and_rounds(contributions)
      min_panelists = expect.fetch("min_panelists", 3).to_i
      min_rounds = expect.fetch("min_rounds", 2).to_i
      require_final_synthesis = expect.fetch("require_final_synthesis", true)
      final_synthesis_present = input.dig("moderation", "final_synthesis_present") == true

      passed = panelists.length >= min_panelists &&
               rounds.length >= min_rounds &&
               (!require_final_synthesis || final_synthesis_present)

      {
        "status" => passed ? "ok" : "error",
        "passed" => passed,
        "details" => {
          "panelist_count" => panelists.length,
          "round_count" => rounds.length,
          "final_synthesis_present" => final_synthesis_present
        }
      }
    rescue StandardError => e
      _error_observation("debate_orchestration_oracle_error", e.message)
    end

    def _assistant_followup_fields(input)
      query = input.dig("follow_up", "query").to_s
      resolved_content_ref = input.dig("follow_up", "resolved_content_ref").to_s
      history_refs = Array(input.fetch("conversation_history", [])).map do |record|
        record.dig("outcome_summary", "content_ref").to_s
      end.reject(&:empty?)
      [query, resolved_content_ref, history_refs]
    end

    def _assistant_query_requires_ref?(followup_query)
      followup_query.match?(/\b(that|it|previous|format|summarize)\b/i)
    end

    def _assistant_resolved_from_history?(resolved_content_ref, history_refs)
      !resolved_content_ref.empty? && history_refs.include?(resolved_content_ref)
    end

    def _provenance_source_violations(sources:, required_keys:, allowed_modes:)
      missing_key_count = 0
      invalid_mode_count = 0

      sources.each do |source|
        source_hash = source.transform_keys(&:to_s)
        missing_key_count += required_keys.count { |key| source_hash.fetch(key.to_s, "").to_s.empty? }
        invalid_mode_count += 1 unless allowed_modes.include?(source_hash.fetch("retrieval_mode", "").to_s)
      end

      [missing_key_count, invalid_mode_count]
    end

    def _debate_panelists_and_rounds(contributions)
      panelists = contributions.map { |item| item.fetch("panelist", "").to_s }.reject(&:empty?).uniq
      rounds = contributions.map { |item| item.fetch("round", 0).to_i }.uniq
      [panelists, rounds]
    end

    def _evaluate_live_outcome_value_oracle(oracle, context)
      step = _live_step_for_oracle!(oracle.fetch("input"), context)
      outcome = _live_step_outcome(step)
      value_path = oracle.fetch("input").fetch("value_path", "")
      observed = _live_path_lookup(outcome.fetch("value"), value_path)
      expected = oracle.fetch("expect").fetch("value")
      tolerance = oracle.fetch("expect").fetch("tolerance", 0.0).to_f
      passed, delta = _value_comparison(observed: observed, expected: expected, tolerance: tolerance)

      {
        "status" => passed ? "ok" : "error",
        "passed" => passed,
        "details" => {
          "step_id" => step.fetch("step_id"),
          "expected" => expected,
          "observed" => observed,
          "delta" => delta,
          "tolerance" => tolerance
        }
      }
    rescue StandardError => e
      _error_observation("live_outcome_value_oracle_error", e.message)
    end

    def _evaluate_live_outcome_error_oracle(oracle, context)
      step = _live_step_for_oracle!(oracle.fetch("input"), context)
      outcome = _live_step_outcome(step)
      expect = oracle.fetch("expect")
      expected_error_type = expect.fetch("error_type").to_s
      expected_retriable = expect.key?("retriable") ? expect.fetch("retriable") : nil

      status_is_error = outcome.fetch("status").to_s == "error"
      error_type_ok = outcome.fetch("error_type").to_s == expected_error_type
      retriable_ok = expected_retriable.nil? || outcome.fetch("retriable") == expected_retriable
      passed = status_is_error && error_type_ok && retriable_ok

      {
        "status" => passed ? "ok" : "error",
        "passed" => passed,
        "details" => {
          "step_id" => step.fetch("step_id"),
          "expected_error_type" => expected_error_type,
          "observed_error_type" => outcome.fetch("error_type"),
          "observed_status" => outcome.fetch("status"),
          "expected_retriable" => expected_retriable,
          "observed_retriable" => outcome.fetch("retriable")
        }
      }
    rescue StandardError => e
      _error_observation("live_outcome_error_oracle_error", e.message)
    end

    # rubocop:disable Metrics/AbcSize
    def _evaluate_live_provenance_envelope_oracle(oracle, context)
      step = _live_step_for_oracle!(oracle.fetch("input"), context)
      outcome = _live_step_outcome(step)
      value = outcome.fetch("value")
      required_keys = Array(oracle.fetch("expect").fetch("required_source_keys", %w[uri fetched_at retrieval_tool retrieval_mode]))
      allowed_modes = Array(oracle.fetch("expect").fetch("allowed_retrieval_modes", %w[live cached fixture knowledge_base]))
      min_sources = oracle.fetch("expect").fetch("min_sources", 1).to_i
      sources = Array(_live_path_lookup(value, "provenance.sources"))
      missing_key_count, invalid_mode_count = _provenance_source_violations(
        sources: sources,
        required_keys: required_keys,
        allowed_modes: allowed_modes
      )
      passed = sources.length >= min_sources && missing_key_count.zero? && invalid_mode_count.zero?

      {
        "status" => passed ? "ok" : "error",
        "passed" => passed,
        "details" => {
          "step_id" => step.fetch("step_id"),
          "source_count" => sources.length,
          "min_sources" => min_sources,
          "missing_key_count" => missing_key_count,
          "invalid_mode_count" => invalid_mode_count
        }
      }
    rescue StandardError => e
      _error_observation("live_provenance_oracle_error", e.message)
    end
    # rubocop:enable Metrics/AbcSize

    def _evaluate_live_continuity_ref_resolution_oracle(oracle, context)
      input = oracle.fetch("input")
      expect = oracle.fetch("expect")
      source_step = _live_step_for_oracle!(input.fetch("source_step"), context, allow_symbol_reference: false)
      follow_up_step = _live_step_for_oracle!(input.fetch("follow_up_step"), context, allow_symbol_reference: false)
      source_ref = source_step.dig("trace_entry", "content_store_write_ref").to_s
      read_refs = Array(follow_up_step.dig("trace_entry", "content_store_read_refs")).map(&:to_s).reject(&:empty?)
      required = expect.fetch("requires_content_ref", true)
      passed = !required || (!source_ref.empty? && read_refs.include?(source_ref))

      {
        "status" => passed ? "ok" : "error",
        "passed" => passed,
        "details" => {
          "source_step_id" => source_step.fetch("step_id"),
          "follow_up_step_id" => follow_up_step.fetch("step_id"),
          "source_content_ref" => source_ref,
          "follow_up_read_refs" => read_refs,
          "requires_content_ref" => required
        }
      }
    rescue StandardError => e
      _error_observation("live_continuity_ref_resolution_oracle_error", e.message)
    end

    def _live_step_for_oracle!(input, context, allow_symbol_reference: true)
      context_hash = (context || {}).transform_keys(&:to_s)
      step_results = Array(context_hash.fetch("step_results", []))
      locator = _live_step_locator(
        input: input,
        allow_symbol_reference: allow_symbol_reference,
        step_results: step_results
      )
      step = _find_live_step(step_results: step_results, locator: locator)
      raise ArgumentError, "live step not found" if step.nil?

      step
    end

    def _live_step_locator(input:, allow_symbol_reference:, step_results:)
      input_hash = input.is_a?(Hash) ? input.transform_keys(&:to_s) : { "step" => input.to_s }
      step_id = input_hash["step"].to_s
      step_id = input.to_s if allow_symbol_reference && step_results.any? && step_id.empty? && input.is_a?(String)
      {
        "step_id" => step_id,
        "step_index" => input_hash["step_index"],
        "call_name" => input_hash["call"].to_s
      }
    end

    def _find_live_step(step_results:, locator:)
      by_id = _find_live_step_by_id(step_results: step_results, step_id: locator.fetch("step_id"))
      return by_id unless by_id.nil?

      by_index = _find_live_step_by_index(step_results: step_results, step_index: locator.fetch("step_index"))
      return by_index unless by_index.nil?

      _find_live_step_by_call(step_results: step_results, call_name: locator.fetch("call_name"))
    end

    def _find_live_step_by_id(step_results:, step_id:)
      return nil if step_id.empty?

      step_results.find { |entry| entry.fetch("step_id", "").to_s == step_id }
    end

    def _find_live_step_by_index(step_results:, step_index:)
      return nil if step_index.nil?

      resolved_index = step_index.to_i
      step_results.find { |entry| entry.fetch("step_index", -1).to_i == resolved_index }
    end

    def _find_live_step_by_call(step_results:, call_name:)
      return nil if call_name.empty?

      step_results.find { |entry| entry.fetch("call", "").to_s == call_name }
    end

    def _live_step_outcome(step)
      outcome = step.fetch("outcome")
      raise ArgumentError, "live step outcome must be a Hash" unless outcome.is_a?(Hash)

      outcome.transform_keys(&:to_s)
    end

    def _live_path_lookup(payload, path)
      normalized_path = path.to_s.strip
      return payload if normalized_path.empty?

      normalized_path.split(".").reduce(payload) do |memo, segment|
        return nil if memo.nil?

        _live_lookup_segment(memo, segment)
      end
    end

    def _live_lookup_segment(container, segment)
      return container[segment] || container[segment.to_sym] if container.is_a?(Hash)
      return container[segment.to_i] if container.is_a?(Array) && segment.match?(/\A\d+\z/)

      nil
    end

    def _value_comparison(observed:, expected:, tolerance:)
      if observed.is_a?(Numeric) && expected.is_a?(Numeric)
        delta = (observed.to_f - expected.to_f).abs
        [delta <= tolerance, delta.round(12)]
      else
        [observed == expected, observed == expected ? 0.0 : nil]
      end
    end

    def _evaluate_expression(expression)
      raise SyntaxError, "expression contains unsupported characters" unless expression.match?(%r{\A[0-9.\s+\-*/()a-zA-Z_,]+\z})

      parser = ExpressionParser.new(expression)
      parser.parse
    end

    # Deterministic arithmetic parser used for fixture/replay class-1 packs.
    class ExpressionParser
      def initialize(source)
        @tokens = _tokenize(source)
        @index = 0
      end

      def parse
        value = _parse_expression
        _expect(:eof)
        value
      end

      private

      def _tokenize(source)
        tokens = []
        scanner = StringScanner.new(source)
        until scanner.eos?
          scanner.scan(/\s+/)
          break if scanner.eos?

          if scanner.scan(/[0-9]+(?:\.[0-9]+)?/)
            raw = scanner.matched
            number = raw.include?(".") ? raw.to_f : raw.to_i
            tokens << [:number, number]
          elsif scanner.scan("sqrt")
            tokens << [:identifier, scanner.matched]
          elsif scanner.scan(%r{[+\-*/(),]})
            tokens << [scanner.matched.to_sym, scanner.matched]
          else
            raise SyntaxError, "unexpected token near '#{scanner.peek(8)}'"
          end
        end
        tokens << [:eof, nil]
        tokens
      end

      def _parse_expression
        value = _parse_term
        while %i[+ -].include?(_current_type)
          operator = _consume[0]
          rhs = _parse_term
          value = operator == :+ ? value + rhs : value - rhs
        end
        value
      end

      def _parse_term
        value = _parse_factor
        while %i[* /].include?(_current_type)
          operator = _consume[0]
          rhs = _parse_factor
          value = operator == :* ? value * rhs : value / rhs
        end
        value
      end

      def _parse_factor
        case _current_type
        when :number
          _consume[1]
        when :+
          _consume
          _parse_factor
        when :-
          _consume
          -_parse_factor
        when :"("
          _consume
          value = _parse_expression
          _expect(:")")
          value
        when :identifier
          _parse_function_call
        else
          raise SyntaxError, "unexpected token '#{_current_type}'"
        end
      end

      def _parse_function_call
        identifier = _consume[1]
        _expect(:"(")
        argument = _parse_expression
        _expect(:")")
        case identifier
        when "sqrt"
          Math.sqrt(argument)
        else
          raise NameError, "unsupported function '#{identifier}'"
        end
      end

      def _current_type
        @tokens[@index][0]
      end

      def _consume
        token = @tokens[@index]
        @index += 1
        token
      end

      def _expect(type)
        raise SyntaxError, "expected #{type}, got #{@tokens[@index][0]}" unless _current_type == type

        _consume
      end
    end

    def _error_type_for_exception(error)
      case error
      when ZeroDivisionError
        "zero_division"
      when Math::DomainError
        "domain_error"
      when SyntaxError, NameError
        "parse_error"
      else
        "unknown_error"
      end
    end

    def _error_observation(error_type, message)
      {
        "status" => "error",
        "error_type" => error_type,
        "passed" => false,
        "details" => {
          "message" => message
        }
      }
    end
  end
  # rubocop:enable Metrics/ClassLength
end
