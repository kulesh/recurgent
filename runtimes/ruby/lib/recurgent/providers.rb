# frozen_string_literal: true

require "json"

class Agent
  # Provider abstraction for LLM APIs.
  #
  # Each provider wraps a single SDK and exposes one method:
  #
  #   generate_code(model:, system_prompt:, user_prompt:, tool_schema:) → String
  #
  # The returned string is Ruby code that will be eval'd in the Agent
  # object's binding. Both providers force structured output so the LLM
  # returns JSON with a "code" key — they just use different mechanisms:
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

      # Forces a tool_use response via tool_choice, then extracts the
      # "code" field from the tool's input JSON.
      def generate_code(model:, system_prompt:, user_prompt:, tool_schema:, timeout_seconds: nil)
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

        code = tool_block.input["code"] || tool_block.input[:code]
        return code if code

        input_keys = tool_block.input.respond_to?(:keys) ? tool_block.input.keys.inspect : "unknown"
        raise "Tool response missing `code` field (input keys: #{input_keys})"
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
      def generate_code(model:, system_prompt:, user_prompt:, tool_schema:, timeout_seconds: nil)
        _ = timeout_seconds
        response = @client.responses.create(
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
              schema: tool_schema[:input_schema]
            }
          }
        )
        output_message = response.output.find { |o| o.type.to_s == "message" }
        text_content = output_message&.content&.first
        raise "No output in OpenAI response" unless text_content

        JSON.parse(text_content.text)["code"]
      end
    end
  end
end
