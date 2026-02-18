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
      allow(prepared_agent).to receive(:_prepare_tool_environment!).and_return(nil)

      ticket = described_class.prepare("calculator", dependencies: [{ name: "nokogiri" }], log: false)
      prepared = ticket.await(timeout: 1)

      expect(ticket).to be_a(Agent::PreparationTicket)
      expect(prepared).to be_a(described_class)
      expect(ticket.status).to eq(:ready)
    end
  end
end
