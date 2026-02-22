# frozen_string_literal: true

require "strscan"

class Agent
  # Agent::SimulationCalculatorOracle evaluates deterministic calculator oracles.
  class SimulationCalculatorOracle
    def evaluate(oracle)
      oracle_hash = oracle.transform_keys(&:to_s)
      case oracle_hash.fetch("kind")
      when "calculator_expression"
        _evaluate_expression_oracle(oracle_hash)
      when "calculator_error_case"
        _evaluate_error_oracle(oracle_hash)
      else
        _error_observation("unsupported_oracle_kind", "unsupported oracle kind: #{oracle_hash["kind"]}")
      end
    end

    private

    def _evaluate_expression_oracle(oracle)
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

    def _evaluate_error_oracle(oracle)
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
end
