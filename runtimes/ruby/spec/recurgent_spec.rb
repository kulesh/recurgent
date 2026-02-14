# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "timeout"

RSpec.describe Agent do
  let(:mock_provider) { instance_double(Agent::Providers::Anthropic) }

  before do
    allow(Agent::Providers::Anthropic).to receive(:new).and_return(mock_provider)
    allow(Agent).to receive(:default_log_path).and_return(false)
    Agent.reset_runtime_config!
  end

  def program_payload(code:, dependencies: nil)
    payload = { code: code }
    payload[:dependencies] = dependencies unless dependencies.nil?
    payload
  end

  def stub_llm_response(code, dependencies: nil)
    allow(mock_provider).to receive(:generate_program).and_return(
      program_payload(code: code, dependencies: dependencies)
    )
  end

  def expect_llm_call_with(code:, dependencies: nil, **matchers)
    expect(mock_provider)
      .to receive(:generate_program)
      .with(hash_including(**matchers))
      .and_return(program_payload(code: code, dependencies: dependencies))
  end

  def expect_ok_outcome(outcome, value:)
    expect(outcome).to be_a(Agent::Outcome)
    expect(outcome).to be_ok
    expect(outcome.value).to eq(value)
  end

  def expect_error_outcome(outcome, type:, retriable:)
    expect(outcome).to be_a(Agent::Outcome)
    expect(outcome).to be_error
    expect(outcome.error_type).to eq(type)
    expect(outcome.retriable).to eq(retriable)
    expect(outcome.error_message).not_to be_nil
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

  describe "coordination primitives" do
    it "builds agents via Agent.for" do
      g = described_class.for("calculator")
      expect(g).to be_a(described_class)
      expect(g.inspect).to include("calculator")
    end

    it "accepts contract fields via Agent.for" do
      specialist = described_class.for(
        "pdf specialist",
        purpose: "produce a PDF artifact",
        deliverable: { type: "object", required: %w[path mime bytes] },
        acceptance: [{ assert: "bytes > 0" }],
        failure_policy: { on_error: "fallback", fallback_role: "archiver" }
      )
      expect(specialist.instance_variable_get(:@delegation_contract)).to eq(
        purpose: "produce a PDF artifact",
        deliverable: { type: "object", required: %w[path mime bytes] },
        acceptance: [{ assert: "bytes > 0" }],
        failure_policy: { on_error: "fallback", fallback_role: "archiver" }
      )
      expect(specialist.instance_variable_get(:@delegation_contract_source)).to eq("fields")
    end

    it "merges Agent.for delegation_contract with contract fields (fields win)" do
      specialist = described_class.for(
        "pdf specialist",
        delegation_contract: {
          purpose: "legacy purpose",
          deliverable: { type: "object", required: ["path"] },
          acceptance: [{ assert: "bytes >= 0" }]
        },
        purpose: "produce a PDF artifact",
        acceptance: [{ assert: "bytes > 0" }],
        failure_policy: { on_error: "fallback" }
      )
      expect(specialist.instance_variable_get(:@delegation_contract)).to eq(
        purpose: "produce a PDF artifact",
        deliverable: { type: "object", required: ["path"] },
        acceptance: [{ assert: "bytes > 0" }],
        failure_policy: { on_error: "fallback" }
      )
      expect(specialist.instance_variable_get(:@delegation_contract_source)).to eq("merged")
    end

    it "writes and returns memory via remember and memory" do
      g = described_class.for("calculator")
      g.remember(current_value: 10, mode: "scientific")
      expect(g.memory).to include(current_value: 10, mode: "scientific")
    end

    it "delegates with inherited runtime settings by default" do
      parent = described_class.for("planner", debug: true, max_generation_attempts: 4, provider_timeout_seconds: 45)
      child = parent.delegate("tax expert")
      expect(child).to be_a(described_class)
      expect(child.instance_variable_get(:@role)).to eq("tax expert")
      expect(child.instance_variable_get(:@debug)).to eq(true)
      expect(child.instance_variable_get(:@max_generation_attempts)).to eq(4)
      expect(child.instance_variable_get(:@provider_timeout_seconds)).to eq(45)
      expect(child.instance_variable_get(:@delegation_budget)).to eq(7)
      expect(child.instance_variable_get(:@trace_id)).to eq(parent.instance_variable_get(:@trace_id))
    end

    it "propagates Solver-authored contract fields to delegated specialists" do
      parent = described_class.for("solver")
      child = parent.delegate(
        "pdf specialist",
        purpose: "produce a PDF artifact",
        deliverable: { type: "object", required: %w[path mime bytes] },
        acceptance: [{ assert: "mime == 'application/pdf'" }, { assert: "bytes > 0" }],
        failure_policy: { on_error: "fallback", fallback_role: "archiver" }
      )
      expect(child.instance_variable_get(:@delegation_contract)).to eq(
        purpose: "produce a PDF artifact",
        deliverable: { type: "object", required: %w[path mime bytes] },
        acceptance: [{ assert: "mime == 'application/pdf'" }, { assert: "bytes > 0" }],
        failure_policy: { on_error: "fallback", fallback_role: "archiver" }
      )
      expect(child.instance_variable_get(:@delegation_contract_source)).to eq("fields")
    end

    it "merges delegate delegation_contract with contract fields (fields win)" do
      parent = described_class.for("solver")
      child = parent.delegate(
        "pdf specialist",
        delegation_contract: {
          purpose: "legacy purpose",
          deliverable: { type: "object", required: ["path"] },
          acceptance: [{ assert: "bytes >= 0" }]
        },
        purpose: "produce a PDF artifact",
        acceptance: [{ assert: "bytes > 0" }],
        failure_policy: { on_error: "fallback" }
      )
      expect(child.instance_variable_get(:@delegation_contract)).to eq(
        purpose: "produce a PDF artifact",
        deliverable: { type: "object", required: ["path"] },
        acceptance: [{ assert: "bytes > 0" }],
        failure_policy: { on_error: "fallback" }
      )
      expect(child.instance_variable_get(:@delegation_contract_source)).to eq("merged")
    end

    it "raises when Agent.for delegation_contract type is invalid" do
      expect { described_class.for("pdf specialist", delegation_contract: "invalid") }
        .to raise_error(ArgumentError, /delegation_contract must be a Hash or nil/)
    end

    it "raises when delegate delegation_contract type is invalid" do
      parent = described_class.for("solver")
      expect { parent.delegate("pdf specialist", delegation_contract: "invalid") }
        .to raise_error(ArgumentError, /delegation_contract must be a Hash or nil/)
    end

    it "raises BudgetExceededError when delegation budget is exhausted" do
      parent = described_class.for("planner", delegation_budget: 0)
      expect { parent.delegate("tax expert") }.to raise_error(Agent::BudgetExceededError, /Delegation budget exceeded/)
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

  describe "attribute assignment (obj.foo = val)" do
    it "stores values directly in context without LLM call" do
      g = described_class.new("calculator")
      stub_llm_response("result = nil")
      g.value = 5
      expect(g.memory[:value]).to eq(5)
      expect(mock_provider).not_to have_received(:generate_program)
    end

    it "handles complex values" do
      g = described_class.new("csv_explorer")
      g.rows = [{ name: "apple", price: 1.50 }]
      expect(g.memory[:rows]).to eq([{ name: "apple", price: 1.50 }])
    end
  end

  describe "method calls (obj.foo / obj.foo(args))" do
    it "returns an ok outcome with the generated result" do
      g = described_class.new("calculator")
      stub_llm_response("context[:value] = context.fetch(:value, 0) + 1; result = context[:value]")
      expect_ok_outcome(g.increment, value: 1)
    end

    it "passes positional arguments to generated code" do
      g = described_class.new("calculator")
      g.remember(value: 5)
      stub_llm_response("context[:value] = context.fetch(:value, 0) + args[0]; result = context[:value]")
      expect_ok_outcome(g.increment(3), value: 8)
    end

    it "passes keyword arguments to generated code" do
      g = described_class.new("calculator")
      stub_llm_response("context[:value] = kwargs[:amount]; result = context[:value]")
      expect_ok_outcome(g.set(amount: 10), value: 10)
    end

    it "returns execution error outcome on execution failure" do
      g = described_class.new("calculator")
      stub_llm_response("raise 'boom'")
      expect_error_outcome(g.increment, type: "execution", retriable: false)
    end

    it "returns execution error outcome on missing constant" do
      g = described_class.new("calculator")
      stub_llm_response("result = UndefinedConstant")
      expect_error_outcome(g.something, type: "execution", retriable: false)
    end

    it "returns provider error outcome on provider failure" do
      g = described_class.new("calculator")
      allow(mock_provider).to receive(:generate_program).and_raise(StandardError, "API error")
      expect_error_outcome(g.increment, type: "provider", retriable: true)
    end

    it "returns invalid_code outcome when provider returns nil code" do
      g = described_class.new("calculator")
      stub_llm_response(nil)
      expect_error_outcome(g.increment, type: "invalid_code", retriable: true)
    end

    it "returns invalid_code outcome when provider returns blank code" do
      g = described_class.new("calculator")
      stub_llm_response("  \n\t")
      expect_error_outcome(g.increment, type: "invalid_code", retriable: true)
    end

    it "returns invalid_dependency_manifest outcome when dependencies is not an array" do
      g = described_class.new("calculator")
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "result = 1", dependencies: "nokogiri")
      )

      expect_error_outcome(g.increment, type: "invalid_dependency_manifest", retriable: false)
    end

    it "returns invalid_dependency_manifest outcome on conflicting duplicate gems" do
      g = described_class.new("calculator")
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(
          code: "result = 1",
          dependencies: [
            { name: "nokogiri", version: "~> 1.16" },
            { name: "Nokogiri", version: "~> 1.17" }
          ]
        )
      )

      expect_error_outcome(g.increment, type: "invalid_dependency_manifest", retriable: false)
    end

    it "retries when provider returns nil code and succeeds on next attempt" do
      g = described_class.new("calculator")
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: nil),
        program_payload(code: "result = 42")
      )

      expect_ok_outcome(g.answer, value: 42)
      expect(mock_provider).to have_received(:generate_program).twice
    end

    it "adds corrective retry instructions after an invalid provider payload" do
      g = described_class.new("calculator", max_generation_attempts: 2)
      prompts = []
      allow(mock_provider).to receive(:generate_program) do |payload|
        prompts << payload.fetch(:user_prompt)
        prompts.length == 1 ? program_payload(code: nil) : program_payload(code: "result = 42")
      end

      expect_ok_outcome(g.answer, value: 42)
      expect(prompts.length).to eq(2)
      expect(prompts.first).not_to include("IMPORTANT: Previous generation failed")
      expect(prompts.last).to include("IMPORTANT: Previous generation failed")
      expect(prompts.last).to include("payload MUST contain non-empty `code`")
      expect(prompts.last).to include("error_type \"unsupported_capability\"")
    end

    it "returns invalid_code outcome after retry budget is exhausted" do
      g = described_class.new("calculator", max_generation_attempts: 2)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: nil),
        program_payload(code: nil)
      )

      expect_error_outcome(g.answer, type: "invalid_code", retriable: true)
      expect(mock_provider).to have_received(:generate_program).twice
    end

    it "passes default provider timeout to provider calls" do
      g = described_class.new("calculator")
      expect(mock_provider).to receive(:generate_program).with(hash_including(timeout_seconds: 120.0))
                                                         .and_return(program_payload(code: "result = 1"))
      expect_ok_outcome(g.answer, value: 1)
    end

    it "passes custom provider timeout to provider calls" do
      g = described_class.new("calculator", provider_timeout_seconds: 15)
      expect(mock_provider).to receive(:generate_program).with(hash_including(timeout_seconds: 15))
                                                         .and_return(program_payload(code: "result = 1"))
      expect_ok_outcome(g.answer, value: 1)
    end

    it "classifies timeout failures as timeout outcomes" do
      g = described_class.new("calculator")
      allow(mock_provider).to receive(:generate_program).and_raise(Timeout::Error, "execution expired")
      expect_error_outcome(g.answer, type: "timeout", retriable: true)
    end
  end

  describe "dependency environment behavior" do
    let(:env_manager) { instance_double(Agent::EnvironmentManager) }
    let(:worker_supervisor) { instance_double(Agent::WorkerSupervisor) }

    before do
      allow(env_manager).to receive(:ensure_environment!) do |manifest|
        {
          env_id: "env-#{manifest.map { |dep| dep[:name] }.join("-")}",
          env_dir: "/tmp/recurgent-env",
          environment_cache_hit: false,
          env_prepare_ms: 10.5,
          env_resolve_ms: 5.0,
          env_install_ms: 4.5
        }
      end
      allow(worker_supervisor).to receive(:env_id).and_return("env-httparty-nokogiri")
      allow(worker_supervisor).to receive(:shutdown)
    end

    it "supports additive dependency manifest growth across calls" do
      g = described_class.new("calculator")
      allow(g).to receive(:_environment_manager).and_return(env_manager)
      allow(g).to receive(:_worker_supervisor).and_return(worker_supervisor)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "result = 1", dependencies: [{ name: "nokogiri", version: "~> 1.16" }]),
        program_payload(
          code: "result = 2",
          dependencies: [
            { name: "nokogiri", version: "~> 1.16" },
            { name: "httparty" }
          ]
        ),
        program_payload(code: "result = 3", dependencies: [])
      )
      allow(worker_supervisor).to receive(:execute).and_return(
        {
          status: "ok",
          value: 1,
          context_snapshot: { "value" => 1 },
          worker_pid: 4321,
          worker_restart_count: 0
        },
        {
          status: "ok",
          value: 2,
          context_snapshot: { "value" => 2 },
          worker_pid: 4321,
          worker_restart_count: 0
        },
        {
          status: "ok",
          value: 3,
          context_snapshot: { "value" => 3 },
          worker_pid: 4321,
          worker_restart_count: 0
        }
      )

      expect_ok_outcome(g.step_one, value: 1)
      expect_ok_outcome(g.step_two, value: 2)
      expect_ok_outcome(g.step_three, value: 3)
      expect(env_manager).to have_received(:ensure_environment!).with(
        [{ name: "nokogiri", version: "~> 1.16" }]
      ).once
      expect(env_manager).to have_received(:ensure_environment!).with(
        [
          { name: "httparty", version: ">= 0" },
          { name: "nokogiri", version: "~> 1.16" }
        ]
      ).twice
      expect(worker_supervisor).to have_received(:execute).exactly(3).times
    end

    it "routes through worker when effective manifest is non-empty even if call omits dependencies" do
      g = described_class.new("calculator")
      allow(g).to receive(:_environment_manager).and_return(env_manager)
      allow(g).to receive(:_worker_supervisor).and_return(worker_supervisor)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "result = 1", dependencies: [{ name: "nokogiri", version: "~> 1.16" }]),
        program_payload(code: "result = 2", dependencies: [])
      )
      allow(worker_supervisor).to receive(:execute).and_return(
        {
          status: "ok",
          value: 1,
          context_snapshot: { "value" => 1 },
          worker_pid: 4321,
          worker_restart_count: 0
        },
        {
          status: "ok",
          value: 2,
          context_snapshot: { "value" => 2 },
          worker_pid: 4321,
          worker_restart_count: 0
        }
      )

      expect_ok_outcome(g.step_one, value: 1)
      expect_ok_outcome(g.step_two, value: 2)
      expect(worker_supervisor).to have_received(:execute).twice
      expect(env_manager).to have_received(:ensure_environment!).with(
        [{ name: "nokogiri", version: "~> 1.16" }]
      ).twice
    end

    it "returns dependency_manifest_incompatible for non-additive manifest changes" do
      g = described_class.new("calculator")
      allow(g).to receive(:_environment_manager).and_return(env_manager)
      allow(g).to receive(:_worker_supervisor).and_return(worker_supervisor)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "result = 1", dependencies: [{ name: "nokogiri", version: "~> 1.16" }]),
        program_payload(code: "result = 2", dependencies: [{ name: "nokogiri", version: "~> 1.17" }])
      )
      allow(worker_supervisor).to receive(:execute).and_return(
        {
          status: "ok",
          value: 1,
          context_snapshot: {},
          worker_pid: 4321,
          worker_restart_count: 0
        }
      )

      expect_ok_outcome(g.step_one, value: 1)
      expect_error_outcome(g.step_two, type: "dependency_manifest_incompatible", retriable: false)
      expect(env_manager).to have_received(:ensure_environment!).once
    end

    it "enforces allowed_gems policy before materialization" do
      Agent.configure_runtime(allowed_gems: ["httparty"])
      g = described_class.new("calculator")
      allow(g).to receive(:_environment_manager).and_return(env_manager)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "result = 1", dependencies: [{ name: "nokogiri", version: "~> 1.16" }])
      )

      expect_error_outcome(g.step_one, type: "dependency_policy_violation", retriable: false)
      expect(env_manager).not_to have_received(:ensure_environment!)
    end

    it "enforces blocked_gems policy before materialization" do
      Agent.configure_runtime(blocked_gems: ["nokogiri"])
      g = described_class.new("calculator")
      allow(g).to receive(:_environment_manager).and_return(env_manager)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "result = 1", dependencies: [{ name: "nokogiri", version: "~> 1.16" }])
      )

      expect_error_outcome(g.step_one, type: "dependency_policy_violation", retriable: false)
      expect(env_manager).not_to have_received(:ensure_environment!)
    end

    it "enforces internal_only source mode policy before materialization" do
      Agent.configure_runtime(source_mode: "internal_only", gem_sources: ["https://rubygems.org"])
      g = described_class.new("calculator")
      allow(g).to receive(:_environment_manager).and_return(env_manager)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "result = 1", dependencies: [{ name: "nokogiri", version: "~> 1.16" }])
      )

      expect_error_outcome(g.step_one, type: "dependency_policy_violation", retriable: false)
      expect(env_manager).not_to have_received(:ensure_environment!)
    end

    it "executes dependency-backed programs via worker and updates context snapshot" do
      g = described_class.new("calculator")
      allow(g).to receive(:_environment_manager).and_return(env_manager)
      allow(g).to receive(:_worker_supervisor).and_return(worker_supervisor)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "context[:value] = context.fetch(:value, 0) + 1; result = context[:value]", dependencies: [{ name: "nokogiri" }])
      )
      allow(worker_supervisor).to receive(:execute).and_return(
        {
          status: "ok",
          value: 1,
          context_snapshot: { "value" => 1 },
          worker_pid: 4321,
          worker_restart_count: 0
        }
      )

      outcome = g.increment
      expect_ok_outcome(outcome, value: 1)
      expect(g.memory[:value]).to eq(1)
      expect(worker_supervisor).to have_received(:execute).once
    end

    it "returns non_serializable_result when dependency-backed args fail JSON boundary" do
      g = described_class.new("calculator")
      allow(g).to receive(:_environment_manager).and_return(env_manager)
      allow(g).to receive(:_worker_supervisor).and_return(worker_supervisor)
      allow(worker_supervisor).to receive(:execute)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "result = 1", dependencies: [{ name: "nokogiri" }])
      )

      outcome = g.increment(Object.new)
      expect_error_outcome(outcome, type: "non_serializable_result", retriable: false)
      expect(worker_supervisor).not_to have_received(:execute)
    end

    it "skips worker execution when program has no dependencies" do
      g = described_class.new("calculator")
      allow(g).to receive(:_environment_manager).and_return(env_manager)
      allow(g).to receive(:_worker_supervisor).and_return(worker_supervisor)
      allow(worker_supervisor).to receive(:execute)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "result = 42", dependencies: [])
      )

      expect_ok_outcome(g.compute, value: 42)
      expect(worker_supervisor).not_to have_received(:execute)
    end

    it "returns timeout outcome when worker times out" do
      g = described_class.new("calculator")
      allow(g).to receive(:_environment_manager).and_return(env_manager)
      allow(g).to receive(:_worker_supervisor).and_return(worker_supervisor)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "result = 1", dependencies: [{ name: "nokogiri" }])
      )
      allow(worker_supervisor).to receive(:execute).and_return(
        {
          status: "error",
          error_type: "timeout",
          error_message: "worker timed out",
          worker_pid: 4321,
          worker_restart_count: 1
        }
      )

      expect_error_outcome(g.increment, type: "timeout", retriable: true)
    end
  end

  describe ".prepare" do
    it "returns a preparation ticket that resolves with an agent" do
      prepared_agent = described_class.for("calculator", log: false)
      allow(described_class).to receive(:for).and_return(prepared_agent)
      allow(prepared_agent).to receive(:_prepare_specialist_environment!).and_return(nil)

      ticket = described_class.prepare("calculator", dependencies: [{ name: "nokogiri" }], log: false)
      prepared = ticket.await(timeout: 1)

      expect(ticket).to be_a(Agent::PreparationTicket)
      expect(prepared).to be_a(described_class)
      expect(ticket.status).to eq(:ready)
    end
  end

  describe "delegation" do
    it "allows LLM to return Agent objects" do
      g = described_class.new("debate")
      stub_llm_response(<<~RUBY)
        result = Agent.for("philosopher", model: "claude-sonnet-4-5-20250929", verbose: false)
      RUBY
      outcome = g.discuss
      expect(outcome).to be_ok
      expect(outcome.value).to be_a(described_class)
      expect(outcome.value.instance_variable_get(:@role)).to eq("philosopher")
    end

    it "supports recursive calls where generated code uses Agent" do
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "helper = Agent.for(\"calculator\"); result = helper.add(2, 3)"),
        program_payload(code: "result = args[0] + args[1]")
      )

      g = described_class.new("delegator")
      expect_ok_outcome(g.compute, value: 5)
      expect(mock_provider).to have_received(:generate_program).twice
    end

    it "propagates error outcomes from delegated child calls" do
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "helper = Agent.for(\"child\"); result = helper.respond('x')"),
        program_payload(code: nil),
        program_payload(code: nil)
      )

      g = described_class.new("delegator")
      expect_error_outcome(g.compute, type: "invalid_code", retriable: true)
    end

    it "includes delegate and outcome guidance in system prompt" do
      g = described_class.new("debate")
      expect_llm_call_with(
        code: "result = nil",
        system_prompt: a_string_including("delegate(")
                       .and(including("purpose:"))
                       .and(including("Outcome object"))
                       .and(including("delegation does NOT grant new capabilities"))
      )
      g.discuss
    end

    it "includes delegation example in user prompt" do
      g = described_class.new("debate")
      expect_llm_call_with(
        code: "result = nil",
        user_prompt: a_string_including("delegate(")
                     .and(including("purpose:"))
                     .and(including("analysis.ok?"))
                     .and(including("unsupported_capability"))
      )
      g.discuss
    end
  end

  describe "verbose mode" do
    it "prints generated code to stdout" do
      g = described_class.new("calculator", verbose: true)
      stub_llm_response("result = 42")
      expect { g.answer }.to output(/Generated code/).to_stdout
    end
  end

  describe "#inspect" do
    it "returns a simple string without LLM call" do
      g = described_class.new("calculator")
      expect(g.inspect).to eq("<Agent(calculator) context=[]>")
    end

    it "includes context keys after assignment" do
      g = described_class.new("calculator")
      g.value = 5
      expect(g.inspect).to eq("<Agent(calculator) context=[:value]>")
    end
  end

  describe "#to_s" do
    it "calls LLM for string representation" do
      g = described_class.new("calculator")
      stub_llm_response('result = "Calculator(memory=0)"')
      expect(g.to_s).to eq("Calculator(memory=0)")
    end

    it "returns inspect fallback on API failure" do
      g = described_class.new("calculator")
      allow(mock_provider).to receive(:generate_program).and_raise(StandardError, "API error")
      expect(g.to_s).to eq("<Agent(calculator) context=[]>")
    end
  end

  describe "#respond_to_missing?" do
    it "returns true for setter-like names" do
      g = described_class.new("calculator")
      expect(g).to respond_to(:value=)
    end

    it "returns true for context-backed readers after assignment" do
      g = described_class.new("calculator")
      g.value = 7
      expect(g).to respond_to(:value)
    end

    it "returns false for unknown dynamic methods" do
      g = described_class.new("calculator")
      expect(g).not_to respond_to(:increment)
    end
  end

  describe "prompt construction" do
    it "includes identity in system prompt" do
      g = described_class.new("file_inspector")
      expect_llm_call_with(code: "result = nil", system_prompt: a_string_including("file_inspector"))
      g.read("README.md")
    end

    it "includes context state in user prompt" do
      g = described_class.new("calculator")
      g.value = 5
      expect_llm_call_with(
        code: "result = context[:value]",
        user_prompt: a_string_including("value")
      )
      g.value
    end

    it "sends tool schema via provider" do
      g = described_class.new("calculator")
      expect_llm_call_with(
        code: "result = nil",
        tool_schema: hash_including(name: "execute_code")
      )
      g.something
    end

    it "injects delegated contract guidance into prompts" do
      g = described_class.new(
        "pdf specialist",
        delegation_contract: {
          purpose: "generate a PDF file",
          deliverable: { required: %w[path mime bytes] },
          acceptance: [{ assert: "mime == 'application/pdf'" }],
          failure_policy: { on_error: "fallback" }
        }
      )
      expect_llm_call_with(
        code: "result = nil",
        system_prompt: a_string_including("Solver Delegation Contract").and(including("generate a PDF file")),
        user_prompt: a_string_including("Solver Delegation Contract").and(including("application/pdf"))
      )
      g.convert
    end
  end

  describe "logging" do
    let(:log_dir) { Dir.mktmpdir("recurgent-test-") }
    let(:log_path) { File.join(log_dir, "test.jsonl") }

    after { FileUtils.rm_rf(log_dir) }

    it "writes a JSONL entry with correct fields on method call" do
      g = described_class.new("calculator", log: log_path)
      stub_llm_response("context[:value] = 1; result = context[:value]")
      g.increment

      lines = File.readlines(log_path)
      expect(lines.size).to eq(1)

      entry = JSON.parse(lines.first)
      expect(entry).to include(
        "runtime" => "ruby",
        "role" => "calculator",
        "model" => "claude-sonnet-4-5-20250929",
        "method" => "increment",
        "args" => [],
        "kwargs" => {},
        "contract_source" => "none",
        "code" => "context[:value] = 1; result = context[:value]",
        "generation_attempt" => 1,
        "outcome_status" => "ok"
      )
      expect(entry["trace_id"]).to match(/\A[0-9a-f]{24}\z/)
      expect(entry["call_id"]).to match(/\A[0-9a-f]{16}\z/)
      expect(entry["parent_call_id"]).to be_nil
      expect(entry["depth"]).to eq(0)
      expect(entry["timestamp"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/)
      expect(entry["duration_ms"]).to be_a(Numeric)
      expect(entry).not_to have_key("system_prompt")
      expect(entry).not_to have_key("user_prompt")
      expect(entry).not_to have_key("context")
    end

    it "logs delegated contract metadata when present" do
      g = described_class.new(
        "pdf specialist",
        log: log_path,
        delegation_contract: {
          purpose: "produce PDF",
          deliverable: { type: "object", required: %w[path mime bytes] },
          acceptance: [{ assert: "bytes > 0" }],
          failure_policy: { on_error: "fallback", fallback_role: "archiver" }
        }
      )
      stub_llm_response("result = { path: '/tmp/report.pdf', mime: 'application/pdf', bytes: 123 }")
      g.convert

      entry = JSON.parse(File.readlines(log_path).first)
      expect(entry["contract_source"]).to eq("hash")
      expect(entry["contract_purpose"]).to eq("produce PDF")
      expect(entry["contract_deliverable"]).to include("type" => "object")
      expect(entry["contract_acceptance"]).to eq([{ "assert" => "bytes > 0" }])
      expect(entry["contract_failure_policy"]).to include("on_error" => "fallback")
    end

    it "does not create a file when log: false" do
      g = described_class.new("calculator", log: false)
      stub_llm_response("result = 1")
      g.increment

      expect(Dir.glob(File.join(log_dir, "*"))).to be_empty
    end

    it "includes prompts and context in debug mode" do
      g = described_class.new("calculator", log: log_path, debug: true)
      g.value = 5
      stub_llm_response("context[:value] = context.fetch(:value, 0) + 1; result = context[:value]")
      g.increment

      entry = JSON.parse(File.readlines(log_path).first)
      expect(entry).to have_key("system_prompt")
      expect(entry).to have_key("user_prompt")
      expect(entry).to have_key("context")
      expect(entry["context"]).to eq("value" => 6)
      expect(entry["system_prompt"]).to include("calculator")
      expect(entry["user_prompt"]).to include("increment")
    end

    it "normalizes binary-encoded UTF-8 strings in logged context" do
      g = described_class.new("calculator", log: log_path, debug: true)
      g.remember(binary_text: "agent\u2019s note".dup.force_encoding(Encoding::ASCII_8BIT))
      stub_llm_response("result = :ok")

      expect_ok_outcome(g.echo, value: :ok)

      entry = JSON.parse(File.readlines(log_path).first)
      expect(entry.dig("context", "binary_text")).to eq("agent’s note")
    end

    it "normalizes nested binary-encoded strings in logged context" do
      g = described_class.new("calculator", log: log_path, debug: true)
      nested = "nested insight".dup.force_encoding(Encoding::ASCII_8BIT)
      g.remember(nested: { inner: [nested] })
      stub_llm_response("result = :ok")

      expect_ok_outcome(g.echo, value: :ok)

      entry = JSON.parse(File.readlines(log_path).first)
      expect(entry.dig("context", "nested", "inner", 0)).to eq("nested insight")
    end

    it "logs generation_attempt as retry count when provider succeeds on second attempt" do
      g = described_class.new("calculator", log: log_path, max_generation_attempts: 3)
      allow(mock_provider).to receive(:generate_program).and_return(
        nil,
        program_payload(code: "result = 7")
      )

      expect_ok_outcome(g.answer, value: 7)

      entry = JSON.parse(File.readlines(log_path).first)
      expect(entry["generation_attempt"]).to eq(2)
      expect(entry["code"]).to eq("result = 7")
    end

    it "does not break the caller when logging fails" do
      g = described_class.new("calculator", log: "/dev/null/impossible/path.jsonl")
      stub_llm_response("context[:value] = 1; result = context[:value]")
      expect_ok_outcome(g.increment, value: 1)
    end

    it "surfaces logging failures in debug mode via stderr" do
      g = described_class.new("calculator", log: "/dev/null/impossible/path.jsonl", debug: true)
      stub_llm_response("result = 1")
      expect { g.increment }.to output(/AGENT LOG ERROR/).to_stderr
    end

    it "includes tolerant delegation guidance in system prompt" do
      g = described_class.new("debate", log: log_path, debug: true)
      expect_llm_call_with(
        code: "result = nil",
        system_prompt: a_string_including("Outcome object")
                       .and(including("delegate("))
                       .and(including("purpose:"))
                       .and(including("delegation does NOT grant new capabilities"))
      )
      g.discuss
    end

    it "includes tolerant delegation guidance in user prompt" do
      g = described_class.new("debate", log: log_path)
      expect_llm_call_with(
        code: "result = nil",
        user_prompt: a_string_including("delegate(")
                     .and(including("purpose:"))
                     .and(including("analysis.ok?"))
                     .and(including("unsupported_capability"))
      )
      g.discuss
    end

    it "appends multiple entries to the same file" do
      g = described_class.new("calculator", log: log_path)
      stub_llm_response("context[:value] = context.fetch(:value, 0) + 1; result = context[:value]")
      g.increment
      g.increment

      lines = File.readlines(log_path)
      expect(lines.size).to eq(2)
    end

    it "logs calls when execution returns error outcomes" do
      g = described_class.new("calculator", log: log_path)
      stub_llm_response("raise 'boom'")
      expect_error_outcome(g.increment, type: "execution", retriable: false)

      lines = File.readlines(log_path)
      expect(lines.size).to eq(1)
      entry = JSON.parse(lines.first)
      expect(entry["code"]).to eq("raise 'boom'")
      expect(entry["error_class"]).to eq("Agent::ExecutionError")
      expect(entry["outcome_error_type"]).to eq("execution")
    end

    it "logs parent-child trace linkage for delegated calls" do
      g = described_class.new("delegator", log: log_path)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(
          code: 'specialist = delegate("calculator"); child = specialist.add(2, 3); result = child.ok? ? child.value : child.error_type'
        ),
        program_payload(code: "result = args[0] + args[1]")
      )

      expect_ok_outcome(g.compute, value: 5)

      entries = File.readlines(log_path).map { |line| JSON.parse(line) }
      compute_entry = entries.find { |e| e["method"] == "compute" }
      add_entry = entries.find { |e| e["method"] == "add" }

      expect(compute_entry).not_to be_nil
      expect(add_entry).not_to be_nil
      expect(compute_entry["trace_id"]).to eq(add_entry["trace_id"])
      expect(compute_entry["depth"]).to eq(0)
      expect(add_entry["depth"]).to eq(1)
      expect(add_entry["parent_call_id"]).to eq(compute_entry["call_id"])
    end

    it "logs generation_attempt when provider retries are exhausted" do
      g = described_class.new("calculator", log: log_path, max_generation_attempts: 2)
      allow(mock_provider).to receive(:generate_program).and_return(nil, nil)

      expect_error_outcome(g.answer, type: "invalid_code", retriable: true)

      entry = JSON.parse(File.readlines(log_path).first)
      expect(entry["generation_attempt"]).to eq(2)
      expect(entry["error_class"]).to eq("Agent::InvalidCodeError")
      expect(entry["outcome_error_type"]).to eq("invalid_code")
    end

    it "logs program and normalized dependencies for generated programs" do
      g = described_class.new("calculator", log: log_path)
      env_manager = instance_double(Agent::EnvironmentManager)
      worker_supervisor = instance_double(Agent::WorkerSupervisor)
      allow(g).to receive(:_environment_manager).and_return(env_manager)
      allow(g).to receive(:_worker_supervisor).and_return(worker_supervisor)
      allow(env_manager).to receive(:ensure_environment!).and_return(
        {
          env_id: "env-httparty-nokogiri",
          env_dir: "/tmp/recurgent-env",
          environment_cache_hit: false,
          env_prepare_ms: 12.1,
          env_resolve_ms: 5.2,
          env_install_ms: 6.9
        }
      )
      allow(worker_supervisor).to receive(:execute).and_return(
        {
          status: "ok",
          value: 1,
          context_snapshot: { "value" => 1 },
          worker_pid: 4321,
          worker_restart_count: 0
        }
      )
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(
          code: "result = 1",
          dependencies: [
            { name: "Nokogiri", version: "~> 1.16" },
            { name: "httparty" }
          ]
        )
      )

      expect_ok_outcome(g.answer, value: 1)

      entry = JSON.parse(File.readlines(log_path).first)
      expect(entry["program_dependencies"]).to eq(
        [
          { "name" => "Nokogiri", "version" => "~> 1.16" },
          { "name" => "httparty" }
        ]
      )
      expect(entry["normalized_dependencies"]).to eq(
        [
          { "name" => "httparty", "version" => ">= 0" },
          { "name" => "nokogiri", "version" => "~> 1.16" }
        ]
      )
      expect(entry["env_id"]).to eq("env-httparty-nokogiri")
      expect(entry["environment_cache_hit"]).to eq(false)
      expect(entry["env_prepare_ms"]).to eq(12.1)
      expect(entry["env_resolve_ms"]).to eq(5.2)
      expect(entry["env_install_ms"]).to eq(6.9)
      expect(entry["worker_pid"]).to eq(4321)
      expect(entry["worker_restart_count"]).to eq(0)
    end
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
