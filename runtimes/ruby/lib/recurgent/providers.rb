# frozen_string_literal: true

require "json"
require "timeout"

class Agent
  # Provider abstraction for LLM APIs.
  #
  # Each provider wraps a single SDK and exposes one method:
  #
  #   generate_program(model:, system_prompt:, user_prompt:, tool_schema:) → Hash
  #
  # The returned hash contains:
  #   - code: Ruby code to eval in the Agent binding
  #   - dependencies: optional dependency declarations
  #
  # Both providers force structured output through provider-specific APIs:
  #
  #   Anthropic: tool_use with tool_choice (forces a specific tool call)
  #   OpenAI:    Responses API with json_schema structured output
  #
  # Gems are loaded lazily — `require "anthropic"` / `require "openai"`
  # only runs when that provider is instantiated. This keeps the optional
  # openai gem from being required at load time.
  module Providers
    class Anthropic
      def initialize
        require "anthropic"
        @client = ::Anthropic::Client.new
      rescue LoadError
        raise LoadError, 'gem "anthropic" is required for Claude models. Add it to your Gemfile.'
      end

      # Forces a tool_use response via tool_choice, then returns the tool
      # input object for runtime-side validation.
      def generate_program(model:, system_prompt:, user_prompt:, tool_schema:, timeout_seconds: nil)
        params = {
          model: model,
          max_tokens: 2048,
          system_: system_prompt,
          messages: [{ role: "user", content: user_prompt }],
          tools: [tool_schema],
          tool_choice: { type: "tool", name: "execute_code" }
        }
        params[:request_options] = { timeout: timeout_seconds } if timeout_seconds

        message = @client.messages.create(params)
        tool_block = message.content.find { |block| block.type == :tool_use }
        raise "No tool_use block in LLM response" unless tool_block

        tool_block.input
      end
    end

    class OpenAI
      def initialize
        require "openai"
        @client = ::OpenAI::Client.new
      rescue LoadError
        raise LoadError, 'gem "openai" is required for OpenAI models. Add it to your Gemfile.'
      end

      # Uses the Responses API with json_schema structured output to
      # guarantee the response is valid JSON matching our schema.
      # The response may contain reasoning items (chain-of-thought)
      # before the message — we skip those and find the message output.
      # OpenAI Responses API does not expose a request timeout option here.
      # Enforce runtime timeout externally so provider_timeout_seconds applies.
      def generate_program(model:, system_prompt:, user_prompt:, tool_schema:, timeout_seconds: nil)
        normalized_schema = _openai_strict_schema(tool_schema[:input_schema])

        request = lambda do
          @client.responses.create(
            model: model,
            input: [
              { role: :system, content: system_prompt },
              { role: :user, content: user_prompt }
            ],
            text: {
              format: {
                type: :json_schema,
                name: tool_schema[:name],
                strict: true,
                schema: normalized_schema
              }
            }
          )
        end

        response = timeout_seconds ? Timeout.timeout(timeout_seconds) { request.call } : request.call
        output_message = response.output.find { |o| o.type.to_s == "message" }
        text_content = output_message&.content&.first
        raise "No output in OpenAI response" unless text_content

        JSON.parse(text_content.text)
      end

      private

      # OpenAI strict JSON schema requires every object property to be listed
      # in required. Preserve optional semantics by making optional fields nullable.
      def _openai_strict_schema(schema)
        _normalize_schema_node(schema)
      end

      def _normalize_schema_node(node)
        case node
        when Hash
          normalized = node.transform_values { |value| _normalize_schema_node(value) }
          _normalize_object_schema!(normalized)
          normalized
        when Array
          node.map { |value| _normalize_schema_node(value) }
        else
          node
        end
      end

      def _normalize_object_schema!(schema)
        type_key = _schema_key(schema, "type")
        return unless schema[type_key] == "object"

        properties_key = _schema_key(schema, "properties")
        properties = schema[properties_key]
        return unless properties.is_a?(Hash)

        required_key = _required_key(schema)
        original_required = Array(schema[required_key]).map(&:to_s)

        properties.each do |property_name, property_schema|
          next if original_required.include?(property_name.to_s)

          _mark_property_nullable!(property_schema)
        end

        schema[required_key] = properties.keys.map(&:to_s)
      end

      def _mark_property_nullable!(property_schema)
        return unless property_schema.is_a?(Hash)

        type_key = _type_key(property_schema)
        return if type_key.nil?

        property_schema[type_key] = _nullable_types(property_schema[type_key])
      end

      def _type_key(schema)
        return "type" if schema.key?("type")
        return :type if schema.key?(:type)

        nil
      end

      def _nullable_types(type_value)
        types = Array(type_value).map(&:to_s)
        types << "null" unless types.include?("null")
        types.length == 1 ? types.first : types
      end

      def _schema_key(schema, key_name)
        return key_name if schema.key?(key_name)

        key_name.to_sym
      end

      def _required_key(schema)
        schema.key?("required") ? "required" : :required
      end
    end
  end
end
