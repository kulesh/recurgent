# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "timeout"

RSpec.describe Agent do
  let(:mock_provider) { instance_double(Agent::Providers::Anthropic) }
  let(:runtime_toolstore_root) { Dir.mktmpdir("recurgent-spec-toolstore-") }

  before do
    allow(Agent::Providers::Anthropic).to receive(:new).and_return(mock_provider)
    allow(Agent).to receive(:default_log_path).and_return(false)
    Agent.reset_runtime_config!
    Agent.configure_runtime(toolstore_root: runtime_toolstore_root)
  end

  after do
    FileUtils.rm_rf(runtime_toolstore_root)
    Agent.reset_runtime_config!
  end

  describe Agent::Providers::Anthropic do
    # anthropic gem is available but no longer auto-loaded at require time
    before { require "anthropic" }

    # Override the top-level mock so we get real provider instances here
    let(:mock_provider) { nil }

    let(:mock_client) { double("Client") }
    let(:mock_messages) { double("Messages") }

    before do
      allow(Agent::Providers::Anthropic).to receive(:new).and_call_original
      allow(Anthropic::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:messages).and_return(mock_messages)
    end

    it "calls Anthropic Messages API and extracts code" do
      tool_block = double("ToolUseBlock", type: :tool_use, input: { "code" => "result = 42" })
      message = double("Message", content: [tool_block])
      allow(mock_messages).to receive(:create).and_return(message)

      provider = described_class.new
      payload = provider.generate_program(
        model: "claude-sonnet-4-5-20250929",
        system_prompt: "test",
        user_prompt: "test",
        tool_schema: { name: "execute_code", description: "test", input_schema: {} }
      )
      expect(payload).to eq({ "code" => "result = 42" })
    end

    it "passes request timeout to Anthropic request options when configured" do
      tool_block = double("ToolUseBlock", type: :tool_use, input: { "code" => "result = 42" })
      message = double("Message", content: [tool_block])
      expect(mock_messages).to receive(:create).with(hash_including(request_options: { timeout: 12.5 })).and_return(message)

      provider = described_class.new
      provider.generate_program(
        model: "claude-sonnet-4-5-20250929",
        system_prompt: "test",
        user_prompt: "test",
        tool_schema: { name: "execute_code", description: "test", input_schema: {} },
        timeout_seconds: 12.5
      )
    end

    it "returns the tool payload when tool response omits the code field" do
      tool_block = double("ToolUseBlock", type: :tool_use, input: { "not_code" => "x" })
      message = double("Message", content: [tool_block])
      allow(mock_messages).to receive(:create).and_return(message)

      provider = described_class.new
      payload = provider.generate_program(
        model: "claude-sonnet-4-5-20250929",
        system_prompt: "test",
        user_prompt: "test",
        tool_schema: { name: "execute_code", description: "test", input_schema: {} }
      )
      expect(payload).to eq({ "not_code" => "x" })
    end

    it "raises when no tool_use block in response" do
      text_block = double("TextBlock", type: :text)
      message = double("Message", content: [text_block])
      allow(mock_messages).to receive(:create).and_return(message)

      provider = described_class.new
      expect do
        provider.generate_program(
          model: "claude-sonnet-4-5-20250929",
          system_prompt: "test",
          user_prompt: "test",
          tool_schema: { name: "execute_code", description: "test", input_schema: {} }
        )
      end.to raise_error("No tool_use block in LLM response")
    end
  end

  describe Agent::Providers::OpenAI do
    let(:mock_openai_client) { double("OpenAIClient") }
    let(:mock_responses) { double("Responses") }

    before do
      # openai gem is optional and not installed in dev; stub the require and constant
      allow_any_instance_of(described_class).to receive(:require).with("openai").and_return(true)
      stub_const("OpenAI::Client", Class.new)
      allow(OpenAI::Client).to receive(:new).and_return(mock_openai_client)
      allow(mock_openai_client).to receive(:responses).and_return(mock_responses)
    end

    def stub_responses_api(code_string)
      text_content = double("TextContent", text: %({"code": #{code_string.to_json}}))
      output_message = double("OutputMessage", type: "message", content: [text_content])
      double("Response", output: [output_message])
    end

    it "calls OpenAI Responses API and extracts code" do
      response = stub_responses_api("result = 42")
      allow(mock_responses).to receive(:create).and_return(response)

      provider = described_class.new
      payload = provider.generate_program(
        model: "gpt-4o",
        system_prompt: "test",
        user_prompt: "test",
        tool_schema: { name: "execute_code", description: "test", input_schema: {} }
      )
      expect(payload).to eq({ "code" => "result = 42" })
    end

    it "raises when no output in response" do
      response = double("Response", output: [double("OutputMessage", type: "message", content: [])])
      allow(mock_responses).to receive(:create).and_return(response)

      provider = described_class.new
      expect do
        provider.generate_program(
          model: "gpt-4o",
          system_prompt: "test",
          user_prompt: "test",
          tool_schema: { name: "execute_code", description: "test", input_schema: {} }
        )
      end.to raise_error("No output in OpenAI response")
    end

    it "sends structured output schema derived from tool_schema" do
      response = stub_responses_api("result = 1")
      schema = {
        type: "object",
        properties: { code: { type: "string", description: "Ruby code to execute" } },
        required: ["code"],
        additionalProperties: false
      }

      expect(mock_responses).to receive(:create).with(
        hash_including(
          text: {
            format: {
              type: :json_schema,
              name: "execute_code",
              strict: true,
              schema: schema
            }
          }
        )
      ).and_return(response)

      provider = described_class.new
      provider.generate_program(
        model: "gpt-4o",
        system_prompt: "test",
        user_prompt: "test",
        tool_schema: {
          name: "execute_code",
          description: "Provide Ruby code to execute",
          input_schema: schema
        }
      )
    end

    it "enforces timeout_seconds with Timeout.timeout" do
      allow(mock_responses).to receive(:create) do |_request|
        sleep 0.05
        stub_responses_api("result = 1")
      end

      provider = described_class.new
      expect do
        provider.generate_program(
          model: "gpt-4o",
          system_prompt: "test",
          user_prompt: "test",
          tool_schema: { name: "execute_code", description: "test", input_schema: {} },
          timeout_seconds: 0.01
        )
      end.to raise_error(Timeout::Error)
    end
  end
end
