# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "timeout"

RSpec.describe Agent, :agent_test_helpers do
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

  describe "#initialize" do
    it "creates with default settings" do
      g = described_class.new("calculator")
      expect(g.inspect).to include("calculator")
    end

    it "accepts custom model and verbose options" do
      g = described_class.new("test", model: "claude-3-opus-20240229", verbose: true)
      expect(g.inspect).to include("test")
    end

    it "accepts explicit provider: keyword" do
      mock_openai = instance_double(Agent::Providers::OpenAI)
      allow(Agent::Providers::OpenAI).to receive(:new).and_return(mock_openai)

      g = described_class.new("test", model: "my-custom-model", provider: :openai)
      expect(g.instance_variable_get(:@provider)).to eq(mock_openai)
    end

    it "raises on unknown provider" do
      expect { described_class.new("test", provider: :gemini) }.to raise_error(ArgumentError, /Unknown provider/)
    end

    it "raises when max_generation_attempts is less than 1" do
      expect { described_class.new("test", max_generation_attempts: 0) }.to raise_error(ArgumentError, /max_generation_attempts/)
    end

    it "accepts guardrail_recovery_budget" do
      g = described_class.new("test", guardrail_recovery_budget: 2)
      expect(g.instance_variable_get(:@guardrail_recovery_budget)).to eq(2)
    end

    it "raises when guardrail_recovery_budget is negative" do
      expect { described_class.new("test", guardrail_recovery_budget: -1) }.to raise_error(ArgumentError, /guardrail_recovery_budget/)
    end

    it "accepts fresh_outcome_repair_budget" do
      g = described_class.new("test", fresh_outcome_repair_budget: 2)
      expect(g.instance_variable_get(:@fresh_outcome_repair_budget)).to eq(2)
    end

    it "raises when fresh_outcome_repair_budget is negative" do
      expect { described_class.new("test", fresh_outcome_repair_budget: -1) }.to raise_error(ArgumentError, /fresh_outcome_repair_budget/)
    end

    it "accepts provider_timeout_seconds" do
      g = described_class.new("test", provider_timeout_seconds: 30.5)
      expect(g.instance_variable_get(:@provider_timeout_seconds)).to eq(30.5)
    end

    it "raises when provider_timeout_seconds is not positive" do
      expect { described_class.new("test", provider_timeout_seconds: 0) }.to raise_error(ArgumentError, /provider_timeout_seconds/)
    end

    it "accepts delegation_budget" do
      g = described_class.new("test", delegation_budget: 3)
      expect(g.instance_variable_get(:@delegation_budget)).to eq(3)
    end

    it "raises when delegation_budget is negative" do
      expect { described_class.new("test", delegation_budget: -1) }.to raise_error(ArgumentError, /delegation_budget/)
    end

    it "accepts delegation_contract metadata" do
      g = described_class.new("test", delegation_contract: { purpose: "summarize evidence", deliverable: { type: "summary" } })
      expect(g.instance_variable_get(:@delegation_contract)).to eq(
        purpose: "summarize evidence",
        deliverable: { type: "summary" }
      )
    end

    it "raises when delegation_contract purpose is blank" do
      expect do
        described_class.new("test", delegation_contract: { purpose: " " })
      end.to raise_error(ArgumentError, /delegation_contract\[:purpose\]/)
    end
  end

  describe "provider auto-detection" do
    let(:mock_openai) { instance_double(Agent::Providers::OpenAI) }

    before do
      allow(Agent::Providers::OpenAI).to receive(:new).and_return(mock_openai)
    end

    it "selects Anthropic for claude- models" do
      g = described_class.new("test", model: "claude-sonnet-4-5-20250929")
      expect(g.instance_variable_get(:@provider)).to eq(mock_provider)
    end

    it "selects OpenAI for gpt- models" do
      g = described_class.new("test", model: "gpt-4o")
      expect(g.instance_variable_get(:@provider)).to eq(mock_openai)
    end

    it "selects OpenAI for o1- models" do
      g = described_class.new("test", model: "o1-preview")
      expect(g.instance_variable_get(:@provider)).to eq(mock_openai)
    end

    it "selects OpenAI for o3- models" do
      g = described_class.new("test", model: "o3-mini")
      expect(g.instance_variable_get(:@provider)).to eq(mock_openai)
    end

    it "selects OpenAI for o4- models" do
      g = described_class.new("test", model: "o4-mini")
      expect(g.instance_variable_get(:@provider)).to eq(mock_openai)
    end

    it "selects OpenAI for chatgpt- models" do
      g = described_class.new("test", model: "chatgpt-4o-latest")
      expect(g.instance_variable_get(:@provider)).to eq(mock_openai)
    end

    it "defaults to Anthropic for unknown model prefixes" do
      g = described_class.new("test", model: "some-other-model")
      expect(g.instance_variable_get(:@provider)).to eq(mock_provider)
    end

    it "allows explicit provider to override detection" do
      g = described_class.new("test", model: "claude-sonnet-4-5-20250929", provider: :openai)
      expect(g.instance_variable_get(:@provider)).to eq(mock_openai)
    end
  end

  describe "error types" do
    it "defines provider and execution errors" do
      expect(Agent::ProviderError).to be < StandardError
      expect(Agent::InvalidCodeError).to be < Agent::ProviderError
      expect(Agent::TimeoutError).to be < Agent::ProviderError
      expect(Agent::ExecutionError).to be < StandardError
      expect(Agent::BudgetExceededError).to be < StandardError
    end
  end
end
