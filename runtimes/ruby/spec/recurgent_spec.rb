# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "timeout"
require_relative "support/agent_spec_shared_context"

RSpec.describe Agent do
  include_context "agent spec context"

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

  describe "coordination primitives" do
    it "exposes a default self_model before calls" do
      g = described_class.new("calculator")
      expect(g.self_model).to eq(
        awareness_level: "l1",
        authority: {
          observe: true,
          propose: true,
          enact: false
        },
        active_contract_version: nil,
        active_role_profile_version: nil,
        execution_snapshot_ref: nil,
        evolution_snapshot_ref: nil
      )
    end

    it "updates self_model after a call with execution and evolution references" do
      g = described_class.new("calculator")
      stub_llm_response("context[:value] = 1; result = context[:value]")

      expect_ok_outcome(g.increment, value: 1)
      self_model = g.self_model
      expect(self_model[:awareness_level]).to eq("l3")
      expect(self_model[:authority]).to eq(observe: true, propose: true, enact: false)
      expect(self_model[:execution_snapshot_ref]).to include("calculator.increment")
      expect(self_model[:evolution_snapshot_ref]).to include("calculator.increment@sha256:")
    end

    it "persists proposal artifacts without applying runtime mutations" do
      g = described_class.new("planner")
      proposal = g.propose(
        proposal_type: "role_profile_update",
        target: { role: "calculator", version: 2 },
        proposed_diff_summary: "align accumulator slot across sibling methods",
        evidence_refs: ["trace:abc123", "scorecard:calculator.add@sha256:deadbeef"]
      )

      expect(proposal).to include(
        proposal_type: "role_profile_update",
        status: "proposed",
        proposed_diff_summary: "align accumulator slot across sibling methods"
      )
      expect(proposal[:id]).to match(/\Aprop-[0-9a-f]{16}\z/)
      expect(proposal[:target]).to eq(role: "calculator", version: 2)
      expect(proposal[:evidence_refs]).to eq(["trace:abc123", "scorecard:calculator.add@sha256:deadbeef"])

      proposals = g.proposals
      expect(proposals.length).to eq(1)
      stored = g.proposal(proposal[:id])
      expect(stored).to include(
        "proposal_type" => "role_profile_update",
        "status" => "proposed"
      )
      expect(g.runtime_context).to eq({})
    end

    it "returns authority_denied for unauthorized proposal mutation" do
      Agent.configure_runtime(
        toolstore_root: runtime_toolstore_root,
        authority_enforcement_enabled: true,
        authority_maintainers: ["maintainer"]
      )
      g = described_class.new("planner")
      proposal = g.propose(
        proposal_type: "policy_tuning_suggestion",
        target: { policy: "solver_promotion_v1" },
        proposed_diff_summary: "raise min_contract_pass_rate to 0.97",
        evidence_refs: ["trace:def456"]
      )

      outcome = g.apply_proposal(proposal[:id], actor: "intruder")
      expect_error_outcome(outcome, type: "authority_denied", retriable: false)
      expect(outcome.metadata).to include(action: "apply", actor: "intruder")
    end

    it "requires approval before apply and allows maintainer-controlled transitions" do
      Agent.configure_runtime(
        toolstore_root: runtime_toolstore_root,
        authority_enforcement_enabled: true,
        authority_maintainers: ["maintainer"]
      )
      g = described_class.new("planner")
      proposal = g.propose(
        proposal_type: "role_profile_update",
        target: { role: "calculator", version: 3 },
        proposed_diff_summary: "tighten coordination constraint for accumulator slot",
        evidence_refs: ["trace:ghi789"]
      )

      blocked = g.apply_proposal(proposal[:id], actor: "maintainer")
      expect_error_outcome(blocked, type: "invalid_proposal_state", retriable: false)

      approved = g.approve_proposal(proposal[:id], actor: "maintainer", note: "evidence reviewed")
      expect_ok_outcome(approved, value: approved.value)
      expect(approved.value["status"]).to eq("approved")

      applied = g.apply_proposal(proposal[:id], actor: "maintainer", note: "apply approved proposal")
      expect_ok_outcome(applied, value: applied.value)
      expect(applied.value["status"]).to eq("applied")
    end

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

    it "writes and returns runtime context via remember and runtime_context" do
      g = described_class.for("calculator")
      g.remember(current_value: 10, mode: "scientific")
      expect(g.runtime_context).to include(current_value: 10, mode: "scientific")
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

      expect(parent.runtime_context).to include(:tools)
      expect(parent.runtime_context.dig(:tools, "web_fetcher", :purpose)).to eq("fetch and extract content from urls")
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
      expect(parent.runtime_context.dig(:tools, "movie_finder", :intent_signature)).to eq("ask: movies currently in theaters")
      expect(parent.runtime_context.dig(:tools, "movie_finder", :intent_signatures)).to include("ask: movies currently in theaters")
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
        expect(agent.runtime_context.dig(:tools, "rss_parser", :purpose)).to eq("parse RSS/XML feed strings into structured article data")
      end
    end

    it "quarantines corrupt registry and continues with empty tool registry" do
      Dir.mktmpdir("recurgent-toolstore-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        registry_path = File.join(tmpdir, "registry.json")
        FileUtils.mkdir_p(File.dirname(registry_path))
        File.write(registry_path, "{this-is-invalid-json")

        agent = described_class.for("planner")
        expect(agent.runtime_context[:tools]).to be_nil
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

    it "persists method coherence and version scorecards in registry metadata" do
      Dir.mktmpdir("recurgent-toolstore-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        parent = described_class.for("planner")
        calc = parent.delegate("calculator_tool", purpose: "perform calculator operations")
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(code: "context[:value] = context.fetch(:value, 0) + args[0]; result = context[:value]"),
          program_payload(code: "context[:value] = context.fetch(:value, 0) * args[0]; result = context[:value]")
        )

        expect_ok_outcome(calc.add(2), value: 2)
        expect_ok_outcome(calc.multiply(3), value: 6)

        registry = JSON.parse(File.read(File.join(tmpdir, "registry.json")))
        metadata = registry.dig("tools", "calculator_tool")
        expect(metadata["method_state_keys"]).to include("add" => ["value"], "multiply" => ["value"])
        expect(metadata["state_key_consistency_ratio"]).to eq(1.0)
        expect(metadata["namespace_key_collision_count"]).to eq(0)
        expect(metadata["namespace_multi_lifetime_key_count"]).to eq(0)
        expect(metadata["namespace_continuity_violation_count"]).to eq(0)
        expect(metadata["state_key_lifetimes"]).to include("value" => include("role"))
        scorecards = metadata.fetch("version_scorecards")
        expect(scorecards.keys).to include(a_string_matching(/\Aadd@sha256:/), a_string_matching(/\Amultiply@sha256:/))
      end
    end

    it "tracks namespace pressure metrics for state-key drift and mixed inferred lifetimes" do
      Dir.mktmpdir("recurgent-toolstore-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        parent = described_class.for("planner")
        calc = parent.delegate("calculator_tool", purpose: "perform calculator operations")
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(code: "context[:value] = context.fetch(:value, 0) + args[0]; result = context[:value]"),
          program_payload(code: "context[:memory] = context.fetch(:memory, 0) + args[0]; result = context[:memory]"),
          program_payload(code: "context[:value] = Array(context[:value]); context[:value] << args[0]; result = context[:value]")
        )

        expect_ok_outcome(calc.add(2), value: 2)
        expect_ok_outcome(calc.increment(3), value: 3)
        expect_ok_outcome(calc.record("note"), value: [2, "note"])

        registry = JSON.parse(File.read(File.join(tmpdir, "registry.json")))
        metadata = registry.dig("tools", "calculator_tool")
        expect(metadata["namespace_key_collision_count"]).to eq(2)
        expect(metadata["namespace_multi_lifetime_key_count"]).to eq(1)
        expect(metadata["namespace_continuity_violation_count"]).to be >= 1
        expect(metadata.dig("state_key_lifetimes", "value")).to include("role", "session")
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
        scorecards = artifact.fetch("scorecards")
        expect(scorecards).to be_a(Hash)
        expect(scorecards).to have_key(artifact["code_checksum"])
        scorecard = scorecards.fetch(artifact["code_checksum"])
        expect(scorecard["calls"]).to eq(1)
        expect(scorecard["successes"]).to eq(1)
        expect(scorecard["failures"]).to eq(0)
        expect(scorecard["short_window"]).to be_an(Array)
        expect(scorecard["medium_window"]).to be_an(Array)
        expect(scorecard["sessions"]).to be_an(Array)
        expect(scorecard["state_key_consistency_ratio"]).to be_a(Numeric)
        expect(artifact["history"].size).to eq(1)
        expect(artifact.dig("history", 0, "trigger")).to eq("initial_forge")
      end
    end

    it "persists shadow lifecycle state and decision ledger for artifact versions" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        g = described_class.new("calculator")
        stub_llm_response("result = 42")

        expect_ok_outcome(g.answer, value: 42)

        artifact_path = g.send(:_toolstore_artifact_path, role_name: "calculator", method_name: "answer")
        artifact = JSON.parse(File.read(artifact_path))
        checksum = artifact.fetch("code_checksum")
        lifecycle = artifact.fetch("lifecycle")
        version_entry = lifecycle.fetch("versions").fetch(checksum)
        expect(lifecycle["policy_version"]).to eq(Agent::PROMOTION_POLICY_VERSION)
        expect(version_entry["lifecycle_state"]).to eq("probation")
        expect(version_entry["last_decision"]).to eq("continue_probation")
        expect(lifecycle.dig("shadow_ledger", "evaluations")).to be_an(Array)
        expect(lifecycle.dig("shadow_ledger", "evaluations")).not_to be_empty
      end
    end

    it "promotes probation artifact to durable in shadow mode when gate passes" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        g = described_class.new("calculator")
        allow(g).to receive(:_promotion_policy_contract).and_return(
          {
            version: Agent::PROMOTION_POLICY_VERSION,
            min_calls: 1,
            min_sessions: 1,
            min_contract_pass_rate: 0.0,
            max_guardrail_retry_exhausted: 100,
            max_outcome_retry_exhausted: 100,
            max_wrong_boundary_count: 100,
            max_provenance_violations: 100,
            min_state_key_consistency_ratio: 0.0
          }
        )
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(code: "result = 1"),
          program_payload(code: "result = 1")
        )

        expect_ok_outcome(g.answer, value: 1)
        expect_ok_outcome(g.answer, value: 1)

        artifact_path = g.send(:_toolstore_artifact_path, role_name: "calculator", method_name: "answer")
        artifact = JSON.parse(File.read(artifact_path))
        checksum = artifact.fetch("code_checksum")
        version_entry = artifact.dig("lifecycle", "versions", checksum)
        expect(version_entry["lifecycle_state"]).to eq("durable")
        expect(version_entry["last_decision"]).to eq("promote")
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

    it "marks artifacts input-sensitive when generated code bakes values from outcome-wrapped args" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        calc = described_class.new("calculator")

        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(code: "result = 32"),
          program_payload(code: "result = Math.sqrt(32)")
        )

        expect_ok_outcome(calc.sqrt(calc.memory), value: Math.sqrt(32))

        artifact_path = calc.send(:_toolstore_artifact_path, role_name: "calculator", method_name: "sqrt")
        artifact = JSON.parse(File.read(artifact_path))
        expect(artifact["cacheable"]).to eq(false)
        expect(artifact["cacheability_reason"]).to eq("input_baked_code")
        expect(artifact["input_sensitive"]).to eq(true)
      end
    end

    it "marks artifacts input-sensitive when argumented methods ignore args and kwargs" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        calc = described_class.new("calculator")
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(
            code: <<~RUBY
              context[:memory] = context.fetch(:memory, 0) + 1
              result = context[:memory]
            RUBY
          ),
          program_payload(
            code: <<~RUBY
              context[:memory] = context.fetch(:memory, 0) + 1
              result = context[:memory]
            RUBY
          )
        )

        expect_ok_outcome(calc.sqrt(9), value: 1)
        expect_ok_outcome(calc.sqrt(16), value: 2)
        expect(mock_provider).to have_received(:generate_program).twice

        artifact_path = calc.send(:_toolstore_artifact_path, role_name: "calculator", method_name: "sqrt")
        artifact = JSON.parse(File.read(artifact_path))
        expect(artifact["cacheable"]).to eq(false)
        expect(artifact["cacheability_reason"]).to eq("arg_ignored_code")
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
        version_failures = artifact.fetch("scorecards", {}).values.sum { |entry| entry.fetch("failures", 0).to_i }
        expect(version_failures).to eq(2)
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

    it "enforces durable-over-probation artifact selection when promotion enforcement is enabled" do
      Dir.mktmpdir("recurgent-artifacts-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir, promotion_enforcement_enabled: false)
        seeder = described_class.new("calculator")
        stub_llm_response("result = 1")
        expect_ok_outcome(seeder.answer, value: 1)

        artifact_path = seeder.send(:_toolstore_artifact_path, role_name: "calculator", method_name: "answer")
        artifact = JSON.parse(File.read(artifact_path))
        durable_checksum = artifact.fetch("code_checksum")
        durable_code = artifact.fetch("code")
        candidate_code = "result = 99"
        candidate_checksum = seeder.send(:_artifact_code_checksum, candidate_code)

        artifact["code"] = candidate_code
        artifact["code_checksum"] = candidate_checksum
        artifact["versions"] = {
          durable_checksum => { "code" => durable_code, "dependencies" => [] },
          candidate_checksum => { "code" => candidate_code, "dependencies" => [] }
        }
        artifact["lifecycle"] = {
          "policy_version" => Agent::PROMOTION_POLICY_VERSION,
          "incumbent_durable_checksum" => durable_checksum,
          "versions" => {
            durable_checksum => { "lifecycle_state" => "durable", "last_decision" => "promote" },
            candidate_checksum => { "lifecycle_state" => "probation", "last_decision" => "continue_probation" }
          },
          "shadow_ledger" => { "false_promotion_count" => 0, "false_hold_count" => 0, "evaluations" => [] }
        }
        File.write(artifact_path, JSON.generate(artifact))

        Agent.configure_runtime(toolstore_root: tmpdir, promotion_enforcement_enabled: false)
        no_enforcement = described_class.new("calculator")
        expect(mock_provider).not_to receive(:generate_program)
        expect_ok_outcome(no_enforcement.answer, value: 99)

        Agent.configure_runtime(toolstore_root: tmpdir, promotion_enforcement_enabled: true)
        enforced = described_class.new("calculator")
        expect(mock_provider).not_to receive(:generate_program)
        expect_ok_outcome(enforced.answer, value: 1)
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
      expect(g.runtime_context[:value]).to eq(5)
      expect(mock_provider).not_to have_received(:generate_program)
    end

    it "handles complex values" do
      g = described_class.new("csv_explorer")
      g.rows = [{ name: "apple", price: 1.50 }]
      expect(g.runtime_context[:rows]).to eq([{ name: "apple", price: 1.50 }])
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
      expect(g.runtime_context[:value]).to eq(1)
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
      expect(g.to_s).to eq("<Agent(calculator) context=[:conversation_history]>")
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

    it "keeps explicit Agent method surface narrow to protect dynamic dispatch" do
      expect(described_class.instance_methods(false).map(&:to_s).sort).to eq(
        %w[
          apply_proposal approve_proposal define_singleton_method delegate inspect method_missing
          proposal proposals propose reject_proposal remember runtime_context self_model to_s tool
        ]
      )
    end
  end

  describe "capability pattern extraction and memory" do
    it "extracts deterministic capability tags from generated code" do
      g = described_class.new("assistant")
      extraction = g.send(
        :_extract_capability_patterns,
        method_name: "ask",
        role: "assistant",
        code: <<~RUBY,
          require "rss"
          require "rexml/document"
          require "net/http"
          _http = Net::HTTP
          items = [{ "title" => "Story", "link" => "https://example.com/story" }]
          result = items.map { |item| { title: item["title"], link: item["link"] } }
        RUBY
        args: [],
        kwargs: {},
        outcome: nil,
        program_source: "generated"
      )

      expect(extraction[:patterns]).to include(
        "rss_parse",
        "xml_parse",
        "http_fetch",
        "news_headline_extract"
      )
      expect(extraction[:evidence].fetch("rss_parse")).to include("require_rss")
      expect(extraction[:evidence].fetch("http_fetch")).to include("net_http_constant")
    end

    it "quarantines corrupt pattern memory files and recovers with an empty store" do
      g = described_class.new("assistant")
      path = g.send(:_toolstore_patterns_path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "{not-json")

      summaries = g.send(:_recent_pattern_summaries, role: "assistant", method_name: "ask")
      expect(summaries).to eq([])
      expect(Dir.glob("#{path}.corrupt-*")).not_to be_empty
    end
  end
end
