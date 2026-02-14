# frozen_string_literal: true

class Agent
  class GeneratedProgram
    attr_reader :code, :program_dependencies, :normalized_dependencies

    def self.from_provider_payload!(method_name:, payload:)
      unless payload.is_a?(Hash)
        raise InvalidCodeError,
              "Provider returned invalid program for #{method_name} (provider returned #{payload.class}; expected object)"
      end

      code = payload[:code] || payload["code"]
      _validate_code!(method_name, code)

      dependencies = payload.key?(:dependencies) ? payload[:dependencies] : payload["dependencies"]
      normalized_dependencies = DependencyManifest.normalize!(dependencies)

      new(
        code: code,
        program_dependencies: dependencies || [],
        normalized_dependencies: normalized_dependencies
      )
    end

    def initialize(code:, program_dependencies:, normalized_dependencies:)
      @code = code
      @program_dependencies = program_dependencies
      @normalized_dependencies = normalized_dependencies
    end

    def self._validate_code!(method_name, code)
      return if code.is_a?(String) && !code.strip.empty?

      detail =
        if code.nil?
          "provider returned nil `code`"
        elsif !code.is_a?(String)
          "provider returned #{code.class} for `code`"
        else
          "provider returned blank `code`"
        end

      raise InvalidCodeError, "Provider returned invalid code for #{method_name} (#{detail}; expected non-empty String)"
    end
  end
end
