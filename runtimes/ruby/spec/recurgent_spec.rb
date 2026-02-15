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
      tool = described_class.for(
        "pdf tool",
        purpose: "produce a PDF artifact",
        deliverable: { type: "object", required: %w[path mime bytes] },
        acceptance: [{ assert: "bytes > 0" }],
        failure_policy: { on_error: "fallback", fallback_role: "archiver" }
      )
      expect(tool.instance_variable_get(:@delegation_contract)).to eq(
        purpose: "produce a PDF artifact",
        deliverable: { type: "object", required: %w[path mime bytes] },
        acceptance: [{ assert: "bytes > 0" }],
        failure_policy: { on_error: "fallback", fallback_role: "archiver" }
      )
      expect(tool.instance_variable_get(:@delegation_contract_source)).to eq("fields")
    end

    it "merges Agent.for delegation_contract with contract fields (fields win)" do
      tool = described_class.for(
        "pdf tool",
        delegation_contract: {
          purpose: "legacy purpose",
          deliverable: { type: "object", required: ["path"] },
          acceptance: [{ assert: "bytes >= 0" }]
        },
        purpose: "produce a PDF artifact",
        acceptance: [{ assert: "bytes > 0" }],
        failure_policy: { on_error: "fallback" }
      )
      expect(tool.instance_variable_get(:@delegation_contract)).to eq(
        purpose: "produce a PDF artifact",
        deliverable: { type: "object", required: ["path"] },
        acceptance: [{ assert: "bytes > 0" }],
        failure_policy: { on_error: "fallback" }
      )
      expect(tool.instance_variable_get(:@delegation_contract_source)).to eq("merged")
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

    it "registers delegated tools in memory for reuse hints" do
      parent = described_class.for("planner")
      parent.delegate("web_fetcher", purpose: "fetch and extract content from urls")

      expect(parent.memory).to include(:tools)
      expect(parent.memory.dig(:tools, "web_fetcher", :purpose)).to eq("fetch and extract content from urls")
    end

    it "materializes a registered tool via tool(name) using stored contract metadata" do
      parent = described_class.for("planner")
      parent.delegate(
        "web_fetcher",
        purpose: "fetch and parse web content from urls",
        deliverable: { type: "object", required: %w[status content] },
        acceptance: [{ assert: "status indicates success or failure" }],
        failure_policy: { on_error: "return_error" }
      )

      fetched_tool = parent.tool("web_fetcher")
      expect(fetched_tool).to be_a(described_class)
      expect(fetched_tool.instance_variable_get(:@delegation_contract)).to eq(
        purpose: "fetch and parse web content from urls",
        deliverable: { type: "object", required: %w[status content] },
        acceptance: [{ assert: "status indicates success or failure" }],
        failure_policy: { on_error: "return_error" }
      )
    end

    it "raises when tool(name) is called for an unknown registered tool" do
      parent = described_class.for("planner")
      expect { parent.tool("missing_tool") }.to raise_error(ArgumentError, /Unknown tool 'missing_tool'/)
    end

    it "propagates Tool Builder-authored contract fields to delegated tools" do
      parent = described_class.for("tool_builder")
      child = parent.delegate(
        "pdf tool",
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
      parent = described_class.for("tool_builder")
      child = parent.delegate(
        "pdf tool",
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
      expect { described_class.for("pdf tool", delegation_contract: "invalid") }
        .to raise_error(ArgumentError, /delegation_contract must be a Hash or nil/)
    end

    it "raises when delegate delegation_contract type is invalid" do
      parent = described_class.for("tool_builder")
      expect { parent.delegate("pdf tool", delegation_contract: "invalid") }
        .to raise_error(ArgumentError, /delegation_contract must be a Hash or nil/)
    end

    it "raises BudgetExceededError when delegation budget is exhausted" do
      parent = described_class.for("planner", delegation_budget: 0)
      expect { parent.delegate("tax expert") }.to raise_error(Agent::BudgetExceededError, /Delegation budget exceeded/)
    end
  end

  describe "tool registry persistence" do
    it "persists delegated tool metadata to disk when toolstore is enabled" do
      Dir.mktmpdir("recurgent-toolstore-") do |tmpdir|
        Agent.configure_runtime(toolstore_enabled: true, toolstore_root: tmpdir)

        parent = described_class.for("planner")
        parent.delegate(
          "web_fetcher",
          purpose: "fetch and parse web content from urls",
          deliverable: { type: "object", required: %w[status body] },
          acceptance: [{ assert: "status and body are present" }],
          failure_policy: { on_error: "return_error" }
        )

        registry_path = File.join(tmpdir, "registry.json")
        expect(File).to exist(registry_path)
        persisted = JSON.parse(File.read(registry_path))
        expect(persisted["schema_version"]).to eq(Agent::TOOLSTORE_SCHEMA_VERSION)
        expect(persisted.dig("tools", "web_fetcher", "purpose")).to eq("fetch and parse web content from urls")
      end
    end

    it "hydrates tools from persisted registry on startup" do
      Dir.mktmpdir("recurgent-toolstore-") do |tmpdir|
        Agent.configure_runtime(toolstore_enabled: true, toolstore_root: tmpdir)
        registry_path = File.join(tmpdir, "registry.json")
        FileUtils.mkdir_p(File.dirname(registry_path))
        File.write(
          registry_path,
          JSON.generate(
            schema_version: Agent::TOOLSTORE_SCHEMA_VERSION,
            tools: {
              "rss_parser" => {
                purpose: "parse RSS/XML feed strings into structured article data",
                deliverable: { type: "object", required: ["items"] }
              }
            }
          )
        )

        agent = described_class.for("planner")
        expect(agent.memory.dig(:tools, "rss_parser", :purpose)).to eq("parse RSS/XML feed strings into structured article data")
      end
    end

    it "quarantines corrupt registry and continues with empty tool registry" do
      Dir.mktmpdir("recurgent-toolstore-") do |tmpdir|
        Agent.configure_runtime(toolstore_enabled: true, toolstore_root: tmpdir)
        registry_path = File.join(tmpdir, "registry.json")
        FileUtils.mkdir_p(File.dirname(registry_path))
        File.write(registry_path, "{this-is-invalid-json")

        agent = described_class.for("planner")
        expect(agent.memory[:tools]).to be_nil
        expect(Dir.glob("#{registry_path}.corrupt-*")).not_to be_empty
      end
    end

    it "updates registry usage/reliability counters when persisted tool executes" do
      Dir.mktmpdir("recurgent-toolstore-") do |tmpdir|
        Agent.configure_runtime(
          toolstore_enabled: true,
          toolstore_root: tmpdir,
          toolstore_artifact_read_enabled: false
        )
        parent = described_class.for("planner")
        child = parent.delegate("web_fetcher", purpose: "fetch content")

        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(code: "result = 1"),
          program_payload(
            code: <<~RUBY
              result = Agent::Outcome.error(
                error_type: "timeout",
                error_message: "upstream timeout",
                retriable: true
              )
            RUBY
          )
        )

        expect_ok_outcome(child.fetch("a"), value: 1)
        expect_error_outcome(child.fetch("b"), type: "timeout", retriable: true)

        registry = JSON.parse(File.read(File.join(tmpdir, "registry.json")))
        metadata = registry.dig("tools", "web_fetcher")
        expect(metadata["usage_count"]).to be >= 3
        expect(metadata["success_count"]).to be >= 1
        expect(metadata["failure_count"]).to be >= 1
        expect(metadata["last_used_at"]).not_to be_nil
      end
    end
  end

  describe "artifact persistence" do
    it "writes method artifact with generated code and success metrics when toolstore is enabled" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_enabled: true, toolstore_root: tmpdir)
        g = described_class.new("calculator")
        stub_llm_response("result = 42")

        outcome = g.answer
        expect_ok_outcome(outcome, value: 42)

        artifact_path = g.send(:_toolstore_artifact_path, role_name: "calculator", method_name: "answer")
        expect(File).to exist(artifact_path)
        artifact = JSON.parse(File.read(artifact_path))
        expect(artifact["role"]).to eq("calculator")
        expect(artifact["method_name"]).to eq("answer")
        expect(artifact["code"]).to eq("result = 42")
        expect(artifact["prompt_version"]).to eq(Agent::PROMPT_VERSION)
        expect(artifact["runtime_version"]).to eq(Agent::VERSION)
        expect(artifact["success_count"]).to eq(1)
        expect(artifact["failure_count"]).to eq(0)
        expect(artifact["history"].size).to eq(1)
        expect(artifact.dig("history", 0, "trigger")).to eq("initial_forge")
      end
    end

    it "tracks adaptive and extrinsic failure classes in artifact metrics" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_enabled: true, toolstore_root: tmpdir)
        g = described_class.new("rss_parser")
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(
            code: <<~RUBY
              result = Agent::Outcome.error(
                error_type: "parse_failed",
                error_message: "feed parse failed",
                retriable: false
              )
            RUBY
          ),
          program_payload(
            code: <<~RUBY
              result = Agent::Outcome.error(
                error_type: "timeout",
                error_message: "upstream timeout",
                retriable: true
              )
            RUBY
          )
        )

        first = g.parse("feed-1")
        second = g.parse("feed-2")

        expect_error_outcome(first, type: "parse_failed", retriable: false)
        expect_error_outcome(second, type: "timeout", retriable: true)

        artifact_path = g.send(:_toolstore_artifact_path, role_name: "rss_parser", method_name: "parse")
        artifact = JSON.parse(File.read(artifact_path))
        expect(artifact["success_count"]).to eq(0)
        expect(artifact["failure_count"]).to eq(2)
        expect(artifact["adaptive_failure_count"]).to eq(1)
        expect(artifact["extrinsic_failure_count"]).to eq(1)
        expect(artifact["intrinsic_failure_count"]).to eq(0)
        expect(artifact["last_failure_class"]).to eq("extrinsic")
        expect(artifact["last_failure_reason"]).to include("upstream timeout")
      end
    end

    it "caps artifact history to latest three generations with lineage links" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_enabled: true, toolstore_root: tmpdir)
        g = described_class.new("calculator")
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(code: "result = 1"),
          program_payload(code: "result = 2"),
          program_payload(code: "result = 3"),
          program_payload(code: "result = 4")
        )

        4.times { g.answer }

        artifact_path = g.send(:_toolstore_artifact_path, role_name: "calculator", method_name: "answer")
        artifact = JSON.parse(File.read(artifact_path))
        history = artifact["history"]
        expect(history.size).to eq(3)
        expect(history[0]["parent_id"]).to eq(history[1]["id"])
        expect(history[1]["parent_id"]).to eq(history[2]["id"])
      end
    end

    it "executes from persisted artifact without calling provider when read path is enabled" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(
          toolstore_enabled: true,
          toolstore_root: tmpdir,
          toolstore_artifact_read_enabled: false
        )
        seeder = described_class.new("calculator")
        stub_llm_response("result = 42")
        expect_ok_outcome(seeder.answer, value: 42)

        Agent.configure_runtime(
          toolstore_enabled: true,
          toolstore_root: tmpdir,
          toolstore_artifact_read_enabled: true
        )
        warm = described_class.new("calculator")
        expect(mock_provider).not_to receive(:generate_program)

        expect_ok_outcome(warm.answer, value: 42)
      end
    end

    it "falls back to generation when persisted artifact fails checksum validation" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(
          toolstore_enabled: true,
          toolstore_root: tmpdir,
          toolstore_artifact_read_enabled: false
        )
        seeder = described_class.new("calculator")
        stub_llm_response("result = 42")
        expect_ok_outcome(seeder.answer, value: 42)

        artifact_path = seeder.send(:_toolstore_artifact_path, role_name: "calculator", method_name: "answer")
        artifact = JSON.parse(File.read(artifact_path))
        artifact["code"] = "result = 12345"
        File.write(artifact_path, JSON.generate(artifact))

        Agent.configure_runtime(
          toolstore_enabled: true,
          toolstore_root: tmpdir,
          toolstore_artifact_read_enabled: true
        )
        fallback = described_class.new("calculator")
        expect(mock_provider).to receive(:generate_program).and_return(program_payload(code: "result = 99"))

        expect_ok_outcome(fallback.answer, value: 99)
      end
    end

    it "repairs persisted adaptive failures when repair is enabled and budget is available" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(
          toolstore_enabled: true,
          toolstore_root: tmpdir,
          toolstore_artifact_read_enabled: false
        )
        seeder = described_class.new("rss_parser")
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(
            code: <<~RUBY
              result = Agent::Outcome.error(
                error_type: "parse_failed",
                error_message: "seed parse failed",
                retriable: false
              )
            RUBY
          )
        )
        expect_error_outcome(seeder.parse("feed"), type: "parse_failed", retriable: false)

        Agent.configure_runtime(
          toolstore_enabled: true,
          toolstore_root: tmpdir,
          toolstore_artifact_read_enabled: true,
          toolstore_repair_enabled: true
        )
        repair_agent = described_class.new("rss_parser")
        expect(mock_provider).to receive(:generate_program).and_return(program_payload(code: 'result = "repaired"'))
        expect_ok_outcome(repair_agent.parse("feed"), value: "repaired")

        artifact_path = repair_agent.send(:_toolstore_artifact_path, role_name: "rss_parser", method_name: "parse")
        artifact = JSON.parse(File.read(artifact_path))
        expect(artifact["repair_count_since_regen"]).to eq(1)
        expect(artifact["last_repaired_at"]).not_to be_nil
        expect(artifact["history"].first["trigger"]).to start_with("repair:")
      end
    end

    it "skips repair and regenerates when repair budget is exhausted" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(
          toolstore_enabled: true,
          toolstore_root: tmpdir,
          toolstore_artifact_read_enabled: false
        )
        seeder = described_class.new("rss_parser")
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(
            code: <<~RUBY
              result = Agent::Outcome.error(
                error_type: "parse_failed",
                error_message: "seed parse failed",
                retriable: false
              )
            RUBY
          )
        )
        expect_error_outcome(seeder.parse("feed"), type: "parse_failed", retriable: false)

        artifact_path = seeder.send(:_toolstore_artifact_path, role_name: "rss_parser", method_name: "parse")
        artifact = JSON.parse(File.read(artifact_path))
        artifact["repair_count_since_regen"] = Agent::MAX_REPAIRS_BEFORE_REGEN
        File.write(artifact_path, JSON.generate(artifact))

        Agent.configure_runtime(
          toolstore_enabled: true,
          toolstore_root: tmpdir,
          toolstore_artifact_read_enabled: true,
          toolstore_repair_enabled: true
        )
        fallback = described_class.new("rss_parser")
        expect(mock_provider).to receive(:generate_program).and_return(program_payload(code: 'result = "generated"'))
        expect_ok_outcome(fallback.parse("feed"), value: "generated")

        updated = JSON.parse(File.read(artifact_path))
        expect(updated["repair_count_since_regen"]).to eq(0)
      end
    end

    it "returns persisted extrinsic failures without repair/regeneration" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(
          toolstore_enabled: true,
          toolstore_root: tmpdir,
          toolstore_artifact_read_enabled: false
        )
        seeder = described_class.new("http_fetcher")
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(
            code: <<~RUBY
              result = Agent::Outcome.error(
                error_type: "timeout",
                error_message: "upstream timeout",
                retriable: true
              )
            RUBY
          )
        )
        expect_error_outcome(seeder.fetch("https://example.com"), type: "timeout", retriable: true)

        Agent.configure_runtime(
          toolstore_enabled: true,
          toolstore_root: tmpdir,
          toolstore_artifact_read_enabled: true,
          toolstore_repair_enabled: true
        )
        warm = described_class.new("http_fetcher")
        expect(mock_provider).not_to receive(:generate_program)
        expect_error_outcome(warm.fetch("https://example.com"), type: "timeout", retriable: true)
      end
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

    it "returns execution error outcome on LoadError" do
      g = described_class.new("calculator")
      stub_llm_response("raise LoadError, 'cannot load such file -- rexml/document'")
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

    it "returns invalid_code outcome when generated code has invalid syntax" do
      g = described_class.new("calculator")
      stub_llm_response("def broken(")
      expect_error_outcome(g.increment, type: "invalid_code", retriable: true)
    end

    it "allows return in generated code" do
      g = described_class.new("calculator")
      stub_llm_response("return 42")
      expect_ok_outcome(g.answer, value: 42)
    end

    it "allows next in generated code via lambda execution context" do
      g = described_class.new("calculator")
      stub_llm_response("next 7")
      expect_ok_outcome(g.answer, value: 7)
    end

    it "supports Agent::Outcome.call as a tolerant success constructor" do
      g = described_class.new("assistant")
      stub_llm_response("result = Agent::Outcome.call(42)")

      outcome = g.answer
      expect_ok_outcome(outcome, value: 42)
      expect(outcome.tool_role).to eq("assistant")
      expect(outcome.method_name).to eq("answer")
    end

    it "accepts hash-like kwargs in Agent::Outcome.call" do
      g = described_class.new("assistant")
      stub_llm_response('result = Agent::Outcome.call(status: 200, content: "ok")')

      expect_ok_outcome(g.fetch, value: { status: 200, content: "ok" })
    end

    it "accepts positional value in Agent::Outcome.ok" do
      g = described_class.new("assistant")
      stub_llm_response('result = Agent::Outcome.ok({status: 200, content: "ok"})')

      expect_ok_outcome(g.fetch, value: { status: 200, content: "ok" })
    end

    it "fills tool context for Agent::Outcome.error when tool_role/method_name are omitted" do
      g = described_class.new("assistant")
      stub_llm_response(<<~RUBY)
        result = Agent::Outcome.error(
          error_type: "unsupported_capability",
          error_message: "Timers are unavailable in this runtime",
          retriable: false
        )
      RUBY

      outcome = g.set_timer
      expect_error_outcome(outcome, type: "unsupported_capability", retriable: false)
      expect(outcome.tool_role).to eq("assistant")
      expect(outcome.method_name).to eq("set_timer")
    end

    it "accepts positional error_type and error_message in Agent::Outcome.error" do
      g = described_class.new("assistant")
      stub_llm_response('result = Agent::Outcome.error("unsupported_capability", "Timers unavailable")')

      outcome = g.set_timer
      expect_error_outcome(outcome, type: "unsupported_capability", retriable: false)
      expect(outcome.error_message).to eq("Timers unavailable")
    end

    it "coerces outcome-shaped hashes into canonical error outcomes" do
      g = described_class.new("assistant")
      stub_llm_response(<<~RUBY)
        result = {
          status: :error,
          error_type: "unsupported_capability",
          error_message: "Timers are unavailable in this runtime",
          retriable: false
        }
      RUBY

      expect_error_outcome(g.set_timer, type: "unsupported_capability", retriable: false)
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

    it "retries when provider returns syntactically invalid code and succeeds on next attempt" do
      g = described_class.new("calculator")
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "def broken("),
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
      allow(prepared_agent).to receive(:_prepare_tool_environment!).and_return(nil)

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

    it "includes top-level control-flow guardrails in system prompt" do
      g = described_class.new("file_inspector")
      expect_llm_call_with(
        code: "result = nil",
        system_prompt: a_string_including("Set `result` or use `return`")
                       .and(including("Avoid `redo` unless in a clearly bounded loop"))
      )
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

    it "includes known tools in system prompt after delegation" do
      g = described_class.new("planner")
      g.delegate("web_fetcher", purpose: "fetch and extract content from urls")

      expect_llm_call_with(
        code: "result = nil",
        system_prompt: a_string_including("Tool Registry Snapshot")
                       .and(including("<known_tools>"))
                       .and(including("- web_fetcher: fetch and extract content from urls"))
                       .and(including("Do NOT call values from `context[:tools]`"))
                       .and(including('tool("tool_name")'))
      )
      g.plan
    end

    it "limits known tools rendered in prompt by KNOWN_TOOLS_PROMPT_LIMIT" do
      g = described_class.new("planner")
      tools = (1..(Agent::KNOWN_TOOLS_PROMPT_LIMIT + 3)).each_with_object({}) do |i, registry|
        registry["tool_#{i}"] = { purpose: "purpose #{i}" }
      end
      g.remember(tools: tools)

      prompt = g.send(:_known_tools_prompt)
      rendered_tools = prompt.lines.grep(/^- /).map { |line| line.sub(/^- /, "").split(":").first }
      expect(rendered_tools.size).to eq(Agent::KNOWN_TOOLS_PROMPT_LIMIT)
      expect(rendered_tools.uniq.size).to eq(Agent::KNOWN_TOOLS_PROMPT_LIMIT)
      expect(prompt).to start_with("<known_tools>\n")
      expect(prompt).to end_with("</known_tools>\n")
    end

    it "ranks known tools by recency-weighted reliability" do
      g = described_class.new("planner")
      now = Time.now.utc
      g.remember(
        tools: {
          "stale_tool" => {
            purpose: "old",
            usage_count: 20,
            success_count: 10,
            failure_count: 10,
            last_used_at: (now - (90 * 86_400)).strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
          },
          "fresh_reliable_tool" => {
            purpose: "best",
            usage_count: 5,
            success_count: 5,
            failure_count: 0,
            last_used_at: now.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
          },
          "fresh_unreliable_tool" => {
            purpose: "noisy",
            usage_count: 5,
            success_count: 1,
            failure_count: 4,
            last_used_at: now.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
          }
        }
      )

      prompt = g.send(:_known_tools_prompt)
      best_index = prompt.index("- fresh_reliable_tool: best")
      noisy_index = prompt.index("- fresh_unreliable_tool: noisy")
      stale_index = prompt.index("- stale_tool: old")
      expect(best_index).to be < noisy_index
      expect(noisy_index).to be < stale_index
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
        "pdf tool",
        delegation_contract: {
          purpose: "generate a PDF file",
          deliverable: { required: %w[path mime bytes] },
          acceptance: [{ assert: "mime == 'application/pdf'" }],
          failure_policy: { on_error: "fallback" }
        }
      )
      expect_llm_call_with(
        code: "result = nil",
        system_prompt: a_string_including("Tool Builder Delegation Contract").and(including("generate a PDF file")),
        user_prompt: a_string_including("<invocation>")
                     .and(including("<active_contract>"))
                     .and(including("application/pdf"))
                     .and(including("<response_contract>"))
      )
      g.convert
    end

    it "renders contracted operating mode for depth-1 system prompts" do
      g = described_class.new(
        "web_fetcher",
        delegation_contract: {
          purpose: "fetch and extract content from urls",
          deliverable: { type: "object", required: %w[status body] },
          acceptance: [{ assert: "status and body are present" }],
          failure_policy: { on_error: "return_error" }
        }
      )

      prompt = g.send(:_build_system_prompt, call_context: { depth: 1 })
      expect(prompt).to include("Tool Builder Delegation Contract:")
      expect(prompt).to include("fetch and extract content from urls")
      expect(prompt).not_to include("No delegation contract is active")
    end

    it "includes bootstrap examples only on first user prompt" do
      g = described_class.new("calculator")
      prompts = []
      allow(mock_provider).to receive(:generate_program) do |payload|
        prompts << payload.fetch(:user_prompt)
        program_payload(code: "result = nil")
      end

      g.first_call
      g.second_call

      expect(prompts.length).to eq(2)
      expect(prompts.first).to include("<examples>")
      expect(prompts.last).not_to include("<examples>")
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

    it "records persisted artifact execution source fields" do
      Dir.mktmpdir("recurgent-log-artifact-") do |tmpdir|
        Agent.configure_runtime(
          toolstore_enabled: true,
          toolstore_root: tmpdir,
          toolstore_artifact_read_enabled: false
        )
        seeder = described_class.new("calculator")
        stub_llm_response("result = 7")
        expect_ok_outcome(seeder.answer, value: 7)

        Agent.configure_runtime(
          toolstore_enabled: true,
          toolstore_root: tmpdir,
          toolstore_artifact_read_enabled: true
        )
        artifact_log = File.join(tmpdir, "artifact-log.jsonl")
        warm = described_class.new("calculator", log: artifact_log)
        expect(mock_provider).not_to receive(:generate_program)
        expect_ok_outcome(warm.answer, value: 7)

        entry = JSON.parse(File.read(artifact_log))
        expect(entry["program_source"]).to eq("persisted")
        expect(entry["artifact_hit"]).to eq(true)
        expect(entry["artifact_prompt_version"]).to eq(Agent::PROMPT_VERSION)
        expect(entry["artifact_contract_fingerprint"]).to eq("none")
      end
    end

    it "records repair attempt and success fields when persisted artifact is repaired" do
      Dir.mktmpdir("recurgent-log-artifact-") do |tmpdir|
        Agent.configure_runtime(
          toolstore_enabled: true,
          toolstore_root: tmpdir,
          toolstore_artifact_read_enabled: false
        )
        seeder = described_class.new("rss_parser")
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(
            code: <<~RUBY
              result = Agent::Outcome.error(
                error_type: "parse_failed",
                error_message: "seed parse failed",
                retriable: false
              )
            RUBY
          )
        )
        expect_error_outcome(seeder.parse("feed"), type: "parse_failed", retriable: false)

        Agent.configure_runtime(
          toolstore_enabled: true,
          toolstore_root: tmpdir,
          toolstore_artifact_read_enabled: true,
          toolstore_repair_enabled: true
        )
        artifact_log = File.join(tmpdir, "repair-log.jsonl")
        repair_agent = described_class.new("rss_parser", log: artifact_log)
        expect(mock_provider).to receive(:generate_program).and_return(program_payload(code: 'result = "repaired"'))
        expect_ok_outcome(repair_agent.parse("feed"), value: "repaired")

        entry = JSON.parse(File.read(artifact_log))
        expect(entry["program_source"]).to eq("repaired")
        expect(entry["repair_attempted"]).to eq(true)
        expect(entry["repair_succeeded"]).to eq(true)
        expect(entry["failure_class"]).to eq("adaptive")
      end
    end

    it "logs delegated contract metadata when present" do
      g = described_class.new(
        "pdf tool",
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
      expect(entry["outcome_value"]).to eq(6)
      expect(entry["system_prompt"]).to include("calculator")
      expect(entry["user_prompt"]).to include("increment")
    end

    it "logs inspect fallback for non-JSON outcome values in debug mode" do
      g = described_class.new("calculator", log: log_path, debug: true)
      stub_llm_response("result = Object.new")

      outcome = g.answer
      expect(outcome).to be_ok
      expect(outcome.value).to be_a(Object)

      entry = JSON.parse(File.readlines(log_path).first)
      expect(entry["outcome_value"]).to be_a(String)
      expect(entry["outcome_value"]).to include("#<Object")
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

    it "includes situational structure and bootstrap examples in user prompt" do
      g = described_class.new("debate", log: log_path)
      expect_llm_call_with(
        code: "result = nil",
        user_prompt: a_string_including("<invocation>")
                     .and(including("<response_contract>"))
                     .and(including("<self_check>"))
                     .and(including("<examples>"))
                     .and(including("delegate("))
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
          code: 'tool = delegate("calculator"); child = tool.add(2, 3); result = child.ok? ? child.value : child.error_type'
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
