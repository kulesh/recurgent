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
      parent = described_class.for(
        "planner",
        debug: true,
        max_generation_attempts: 4,
        guardrail_recovery_budget: 2,
        fresh_outcome_repair_budget: 3,
        provider_timeout_seconds: 45
      )
      child = parent.delegate("tax expert")
      expect(child).to be_a(described_class)
      expect(child.instance_variable_get(:@role)).to eq("tax expert")
      expect(child.instance_variable_get(:@debug)).to eq(true)
      expect(child.instance_variable_get(:@max_generation_attempts)).to eq(4)
      expect(child.instance_variable_get(:@guardrail_recovery_budget)).to eq(2)
      expect(child.instance_variable_get(:@fresh_outcome_repair_budget)).to eq(3)
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

    it "propagates intent_signature into delegated contract and tool registry metadata" do
      parent = described_class.for("tool_builder")
      child = parent.delegate(
        "movie_finder",
        purpose: "fetch movie listings from a source",
        deliverable: { type: "object", required: %w[status movies] },
        acceptance: [{ assert: "movies includes concrete titles when successful" }],
        failure_policy: { on_error: "return_error" },
        intent_signature: "ask: movies currently in theaters"
      )

      expect(child.instance_variable_get(:@delegation_contract)).to include(
        intent_signature: "ask: movies currently in theaters"
      )
      expect(parent.memory.dig(:tools, "movie_finder", :intent_signature)).to eq("ask: movies currently in theaters")
      expect(parent.memory.dig(:tools, "movie_finder", :intent_signatures)).to include("ask: movies currently in theaters")
    end

    it "ignores non-runtime delegate options instead of raising unknown option errors" do
      parent = described_class.for("tool_builder", debug: true)

      child = nil
      expect do
        child = parent.delegate(
          "movie_website_scraper",
          purpose: "fetch and parse movie information from websites",
          methods: {
            search_movies: {
              params: [
                { name: "site_url", type: "string", required: false },
                { name: "query", type: "string", required: false }
              ]
            }
          },
          capabilities: %w[http_fetch html_extract movie_data_parse]
        )
      end.not_to raise_error

      expect(child).to be_a(described_class)
      expect(child.instance_variable_get(:@role)).to eq("movie_website_scraper")
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

    it "raises when remember stores executable values inside context[:tools]" do
      parent = described_class.for("planner")
      expect do
        parent.remember(tools: { "web_fetcher" => { fetch: -> { :ok } } })
      end.to raise_error(Agent::ToolRegistryViolationError, /cannot store executable objects/i)
    end
  end

  describe "tool registry persistence" do
    it "persists delegated tool metadata to disk with toolstore persistence" do
      Dir.mktmpdir("recurgent-toolstore-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)

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
        Agent.configure_runtime(toolstore_root: tmpdir)
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
        Agent.configure_runtime(toolstore_root: tmpdir)
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
        Agent.configure_runtime(toolstore_root: tmpdir)
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
        artifact_path = child.send(:_toolstore_artifact_path, role_name: "web_fetcher", method_name: "fetch")
        artifact = JSON.parse(File.read(artifact_path))
        artifact["runtime_version"] = "force-regenerate"
        File.write(artifact_path, JSON.generate(artifact))
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
    it "writes method artifact with generated code and success metrics with toolstore persistence" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
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
        expect(artifact["cacheable"]).to eq(true)
        expect(artifact["cacheability_reason"]).to eq("stable_method_default")
        expect(artifact["input_sensitive"]).to eq(false)
        expect(artifact["success_count"]).to eq(1)
        expect(artifact["failure_count"]).to eq(0)
        expect(artifact["history"].size).to eq(1)
        expect(artifact.dig("history", 0, "trigger")).to eq("initial_forge")
      end
    end

    it "stores failed-attempt trigger diagnostics in artifact generation history after fresh repair succeeds" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        g = described_class.new("calculator", max_generation_attempts: 1)
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(
            code: <<~RUBY
              value = nil
              value << "x"
              result = value
            RUBY
          ),
          program_payload(code: 'result = "ok"')
        )

        expect_ok_outcome(g.answer, value: "ok")

        artifact_path = g.send(:_toolstore_artifact_path, role_name: "calculator", method_name: "answer")
        artifact = JSON.parse(File.read(artifact_path))
        history_entry = artifact.fetch("history").first
        expect(history_entry["trigger"]).to eq("initial_forge")
        expect(history_entry["trigger_stage"]).to eq("execution")
        expect(history_entry["trigger_error_class"]).to eq("Agent::ExecutionError")
        expect(history_entry["trigger_error_message"]).to include("undefined method")
        expect(history_entry["trigger_attempt_id"]).to eq(1)
      end
    end

    it "persists dynamic methods for observability but does not reuse them from artifacts" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        assistant = described_class.new("assistant")
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(code: 'result = "google run"'),
          program_payload(code: 'result = "yahoo run"')
        )

        expect_ok_outcome(assistant.ask("What's the latest on Google News?"), value: "google run")
        expect_ok_outcome(assistant.ask("What's the latest on Yahoo! News?"), value: "yahoo run")
        expect(mock_provider).to have_received(:generate_program).twice

        artifact_path = assistant.send(:_toolstore_artifact_path, role_name: "assistant", method_name: "ask")
        artifact = JSON.parse(File.read(artifact_path))
        expect(artifact["cacheable"]).to eq(false)
        expect(artifact["cacheability_reason"]).to eq("dynamic_dispatch_method")
        expect(artifact["input_sensitive"]).to eq(true)
      end
    end

    it "tracks adaptive and extrinsic failure classes in artifact metrics" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
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

    it "treats low_utility and wrong_tool_boundary as adaptive failure classes" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        g = described_class.new("movie_finder")
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(
            code: <<~RUBY
              result = Agent::Outcome.error(
                error_type: "low_utility",
                error_message: "parsed output was not useful",
                retriable: false
              )
            RUBY
          ),
          program_payload(
            code: <<~RUBY
              result = Agent::Outcome.error(
                error_type: "wrong_tool_boundary",
                error_message: "request crosses transport and extraction boundaries",
                retriable: false
              )
            RUBY
          )
        )

        first = g.fetch("https://example.com/1")
        second = g.fetch("https://example.com/2")

        expect_error_outcome(first, type: "low_utility", retriable: false)
        expect_error_outcome(second, type: "wrong_tool_boundary", retriable: false)

        artifact_path = g.send(:_toolstore_artifact_path, role_name: "movie_finder", method_name: "fetch")
        artifact = JSON.parse(File.read(artifact_path))
        expect(artifact["failure_count"]).to eq(2)
        expect(artifact["adaptive_failure_count"]).to eq(2)
        expect(artifact["intrinsic_failure_count"]).to eq(0)
        expect(artifact["extrinsic_failure_count"]).to eq(0)
      end
    end

    it "caps artifact history to latest three generations with lineage links" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        g = described_class.new("calculator")
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(code: "result = 1"),
          program_payload(code: "result = 2"),
          program_payload(code: "result = 3"),
          program_payload(code: "result = 4")
        )

        artifact_path = g.send(:_toolstore_artifact_path, role_name: "calculator", method_name: "answer")
        4.times do |i|
          g.answer
          next unless i < 3

          artifact = JSON.parse(File.read(artifact_path))
          artifact["runtime_version"] = "force-regen-#{i}"
          File.write(artifact_path, JSON.generate(artifact))
        end

        artifact = JSON.parse(File.read(artifact_path))
        history = artifact["history"]
        expect(history.size).to eq(3)
        expect(history[0]["parent_id"]).to eq(history[1]["id"])
        expect(history[1]["parent_id"]).to eq(history[2]["id"])
      end
    end

    it "executes from persisted artifact without calling provider" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        seeder = described_class.new("calculator")
        stub_llm_response("result = 42")
        expect_ok_outcome(seeder.answer, value: 42)

        Agent.configure_runtime(toolstore_root: tmpdir)
        warm = described_class.new("calculator")
        expect(mock_provider).not_to receive(:generate_program)

        expect_ok_outcome(warm.answer, value: 42)
      end
    end

    it "falls back to generation when persisted artifact fails checksum validation" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        seeder = described_class.new("calculator")
        stub_llm_response("result = 42")
        expect_ok_outcome(seeder.answer, value: 42)

        artifact_path = seeder.send(:_toolstore_artifact_path, role_name: "calculator", method_name: "answer")
        artifact = JSON.parse(File.read(artifact_path))
        artifact["code"] = "result = 12345"
        File.write(artifact_path, JSON.generate(artifact))

        Agent.configure_runtime(toolstore_root: tmpdir)
        fallback = described_class.new("calculator")
        expect(mock_provider).to receive(:generate_program).and_return(program_payload(code: "result = 99"))

        expect_ok_outcome(fallback.answer, value: 99)
      end
    end

    it "repairs persisted adaptive failures when budget is available" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
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

        Agent.configure_runtime(toolstore_root: tmpdir)
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
        Agent.configure_runtime(toolstore_root: tmpdir)
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

        Agent.configure_runtime(toolstore_root: tmpdir)
        fallback = described_class.new("rss_parser")
        expect(mock_provider).to receive(:generate_program).and_return(program_payload(code: 'result = "generated"'))
        expect_ok_outcome(fallback.parse("feed"), value: "generated")

        updated = JSON.parse(File.read(artifact_path))
        expect(updated["repair_count_since_regen"]).to eq(0)
      end
    end

    it "returns persisted extrinsic failures without repair/regeneration" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
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

        Agent.configure_runtime(toolstore_root: tmpdir)
        warm = described_class.new("http_fetcher")
        expect(mock_provider).not_to receive(:generate_program)
        expect_error_outcome(warm.fetch("https://example.com"), type: "timeout", retriable: true)
      end
    end

    it "enforces deliverable min_items constraints and repairs on next persisted execution" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        contract = {
          purpose: "fetch and parse movie listings",
          deliverable: {
            type: "object",
            required: %w[status movies],
            constraints: {
              properties: {
                movies: { type: "array", min_items: 1 }
              }
            }
          }
        }

        Agent.configure_runtime(toolstore_root: tmpdir)
        seeder = described_class.new("movie_finder", delegation_contract: contract)
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(
            code: <<~RUBY
              result = Agent::Outcome.ok(
                status: "success_no_parse",
                movies: [],
                message: "source reachable but parser extracted no listings"
              )
            RUBY
          )
        )
        seeded = seeder.fetch_listings("https://www.fandango.com")
        expect_error_outcome(seeded, type: "contract_violation", retriable: false)
        expect(seeded.metadata).to include(
          mismatch: "min_items_violation",
          expected_min_items: 1,
          actual_items: 0
        )

        Agent.configure_runtime(toolstore_root: tmpdir)
        warm = described_class.new("movie_finder", delegation_contract: contract)
        expect(mock_provider).to receive(:generate_program).and_return(
          program_payload(
            code: <<~RUBY
              result = {
                status: "success",
                movies: [{ title: "Example Action Film" }]
              }
            RUBY
          )
        )
        repaired = warm.fetch_listings("https://www.fandango.com")
        expect(repaired).to be_ok
        expect(repaired.value[:status]).to eq("success")
        expect(repaired.value[:movies]).to be_an(Array)
        expect(repaired.value[:movies].first[:title]).to eq("Example Action Film")

        artifact_path = warm.send(:_toolstore_artifact_path, role_name: "movie_finder", method_name: "fetch_listings")
        artifact = JSON.parse(File.read(artifact_path))
        expect(artifact["repair_count_since_regen"]).to eq(1)
        expect(artifact["last_repaired_at"]).not_to be_nil
      end
    end
  end

  describe "delegated outcome contract validation" do
    it "accepts symbol/string key equivalence and canonicalizes successful object outputs" do
      tool = described_class.new(
        "web_fetcher",
        delegation_contract: {
          purpose: "fetch and extract content from urls",
          deliverable: { type: "object", required: ["body"] }
        }
      )
      stub_llm_response('result = { body: "ok" }')

      outcome = tool.fetch_url("https://example.com/feed")
      expect_ok_outcome(outcome, value: { body: "ok", "body" => "ok" })
      expect(outcome.value[:body]).to eq("ok")
      expect(outcome.value["body"]).to eq("ok")
    end

    it "returns contract_violation when required keys are missing" do
      tool = described_class.new(
        "web_fetcher",
        delegation_contract: {
          purpose: "fetch and extract content from urls",
          deliverable: { type: "object", required: ["body"] }
        }
      )
      stub_llm_response("result = { status: 200 }")

      outcome = tool.fetch_url("https://example.com/feed")
      expect_error_outcome(outcome, type: "contract_violation", retriable: false)
      expect(outcome.metadata).to include(
        expected_shape: "object",
        actual_shape: "object",
        expected_keys: ["body"],
        mismatch: "missing_required_key"
      )
      expect(outcome.metadata.fetch(:actual_keys)).to include(":status")
    end

    it "returns contract_violation for nil required input with empty success payload" do
      parser = described_class.new(
        "rss_parser",
        delegation_contract: {
          purpose: "parse rss feeds",
          deliverable: { type: "array" }
        }
      )
      stub_llm_response("result = []")

      outcome = parser.parse(nil)
      expect_error_outcome(outcome, type: "contract_violation", retriable: false)
      expect(outcome.metadata).to include(
        expected_shape: "non_nil_input",
        actual_shape: "nil",
        mismatch: "nil_required_input"
      )
    end

    it "does not rewrite tool-authored success status when contract constraints are not violated" do
      finder = described_class.new(
        "movie_finder",
        delegation_contract: {
          purpose: "fetch and parse movie listings",
          deliverable: { type: "object", required: %w[status movies] }
        }
      )
      stub_llm_response(
        <<~RUBY
          result = Agent::Outcome.ok(
            status: "success_no_parse",
            movies: [],
            message: "fetched page but found no listings"
          )
        RUBY
      )

      outcome = finder.fetch_listings("https://www.fandango.com")
      expect(outcome).to be_ok
      expect(outcome.value[:status]).to eq("success_no_parse")
      expect(outcome.value[:movies]).to eq([])
    end

    it "returns contract_violation when top-level array min_items constraint fails" do
      parser = described_class.new(
        "rss_parser",
        delegation_contract: {
          purpose: "parse rss feeds",
          deliverable: { type: "array", min_items: 1 }
        }
      )
      stub_llm_response("result = []")

      outcome = parser.parse("<rss></rss>")
      expect_error_outcome(outcome, type: "contract_violation", retriable: false)
      expect(outcome.metadata).to include(
        mismatch: "min_items_violation",
        expected_shape: "array",
        actual_shape: "array",
        expected_min_items: 1,
        actual_items: 0
      )
      expect(outcome.metadata[:constraint_path]).to eq("deliverable.min_items")
    end

    it "returns contract_violation when constrained object property min_items fails" do
      finder = described_class.new(
        "movie_finder",
        delegation_contract: {
          purpose: "fetch and parse movie listings",
          deliverable: {
            type: "object",
            required: %w[status movies],
            constraints: {
              properties: {
                movies: { type: "array", min_items: 1 }
              }
            }
          }
        }
      )
      stub_llm_response('result = { status: "success_no_parse", movies: [] }')

      outcome = finder.fetch_listings("https://www.fandango.com")
      expect_error_outcome(outcome, type: "contract_violation", retriable: false)
      expect(outcome.metadata).to include(
        mismatch: "min_items_violation",
        expected_shape: "array",
        expected_min_items: 1,
        actual_items: 0
      )
      expect(outcome.metadata[:constraint_path]).to eq("deliverable.constraints.properties.movies.min_items")
    end
  end
end
