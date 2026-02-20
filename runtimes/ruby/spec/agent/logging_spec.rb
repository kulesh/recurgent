# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "timeout"
require_relative "../support/agent_spec_shared_context"

RSpec.describe Agent do
  include_context "agent spec context"
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
      expect(entry["execution_receiver"]).to eq("sandbox")
      expect(entry["trace_id"]).to match(/\A[0-9a-f]{24}\z/)
      expect(entry["call_id"]).to match(/\A[0-9a-f]{16}\z/)
      expect(entry["parent_call_id"]).to be_nil
      expect(entry["depth"]).to eq(0)
      expect(entry["timestamp"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/)
      expect(entry["duration_ms"]).to be_a(Numeric)
      expect(entry["capability_patterns"]).to eq([])
      expect(entry["solver_shape"]).to be_a(Hash)
      expect(entry["solver_shape_complete"]).to eq(true)
      expect(entry["solver_shape_stance"]).to be_a(String)
      expect(entry["solver_shape_promotion_intent"]).to be_a(String)
      expect(entry["self_model"]).to be_a(Hash)
      expect(entry["awareness_level"]).to eq("l3")
      expect(entry["authority"]).to eq(
        "observe" => true,
        "propose" => true,
        "enact" => false
      )
      expect(entry["active_contract_version"]).to be_nil
      expect(entry["active_role_profile_version"]).to be_nil
      expect(entry["role_profile_compliance"]).to be_nil
      expect(entry["role_profile_violation_count"]).to eq(0)
      expect(entry["role_profile_violation_types"]).to eq([])
      expect(entry["role_profile_shadow_mode"]).to eq(false)
      expect(entry["role_profile_enforced"]).to eq(false)
      expect(entry["execution_snapshot_ref"]).to include("calculator.increment")
      expect(entry["evolution_snapshot_ref"]).to include("calculator.increment@sha256:")
      expect(entry["namespace_key_collision_count"]).to eq(0)
      expect(entry["namespace_multi_lifetime_key_count"]).to eq(0)
      expect(entry["namespace_continuity_violation_count"]).to eq(0)
      expect(entry["promotion_policy_version"]).to eq(Agent::PROMOTION_POLICY_VERSION)
      expect(entry["promotion_shadow_mode"]).to eq(true)
      expect(entry["promotion_enforced"]).to eq(false)
      expect(entry["lifecycle_state"]).to be_a(String)
      expect(entry["lifecycle_decision"]).to be_a(String)
      expect(entry["promotion_decision_rationale"]).to be_a(Hash)
      expect(entry).not_to have_key("system_prompt")
      expect(entry).not_to have_key("user_prompt")
      expect(entry).not_to have_key("context")
    end

    it "logs role-profile continuity drift in shadow mode without blocking outcome" do
      profile = {
        role: "calculator",
        version: 1,
        constraints: {
          accumulator_slot: {
            kind: :shared_state_slot,
            methods: %w[add multiply],
            mode: :coordination
          }
        }
      }
      g = described_class.new("calculator", log: log_path, role_profile: profile)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "context[:memory] = context.fetch(:memory, 0) + args[0]; result = context[:memory]"),
        program_payload(code: "context[:value] = context.fetch(:value, 0) + args[0]; result = context[:value]")
      )

      expect_ok_outcome(g.add(2), value: 2)
      expect_ok_outcome(g.multiply(3), value: 3)

      entry = JSON.parse(File.readlines(log_path).last)
      expect(entry["outcome_status"]).to eq("ok")
      expect(entry["active_role_profile_version"]).to eq(1)
      expect(entry["role_profile_shadow_mode"]).to eq(true)
      expect(entry["role_profile_enforced"]).to eq(false)
      expect(entry["role_profile_compliance"]).to include("passed" => false)
      expect(entry["role_profile_violation_count"]).to be >= 1
      expect(entry["role_profile_violation_types"]).to include("shared_state_slot_drift")
      expect(entry["role_profile_correction_hint"]).to be_a(String)
    end

    it "routes enforced role-profile continuity violations through recoverable guardrail retries" do
      Agent.configure_runtime(
        toolstore_root: runtime_toolstore_root,
        role_profile_shadow_mode_enabled: true,
        role_profile_enforcement_enabled: true
      )
      profile = {
        role: "calculator",
        version: 1,
        constraints: {
          accumulator_slot: {
            kind: :shared_state_slot,
            methods: %w[add multiply],
            mode: :coordination
          }
        }
      }
      g = described_class.new("calculator", log: log_path, role_profile: profile, guardrail_recovery_budget: 1)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "context[:memory] = context.fetch(:memory, 0) + args[0]; result = context[:memory]"),
        program_payload(code: "context[:value] = context.fetch(:value, 0) * args[0]; result = context[:value]"),
        program_payload(code: "context[:memory] = context.fetch(:memory, 0) * args[0]; result = context[:memory]")
      )

      expect_ok_outcome(g.add(2), value: 2)
      expect_ok_outcome(g.multiply(3), value: 6)

      entry = JSON.parse(File.readlines(log_path).last)
      expect(entry["outcome_status"]).to eq("ok")
      expect(entry["guardrail_recovery_attempts"]).to eq(1)
      expect(entry["role_profile_shadow_mode"]).to eq(true)
      expect(entry["role_profile_enforced"]).to eq(true)
      expect(entry["role_profile_compliance"]).to include("passed" => true)
      expect(entry["attempt_failures"]).to be_a(Array)
      expect(entry["attempt_failures"].length).to eq(1)
      expect(entry["attempt_failures"].first["error_class"]).to eq("Agent::ToolRegistryViolationError")
      expect(entry["attempt_failures"].first["error_message"]).to include("role_profile_continuity_violation")
      expect(entry["latest_failure_message"]).to include("role_profile_continuity_violation")
    end

    it "emits prescriptive correction hints when canonical values are declared" do
      profile = {
        role: "calculator",
        version: 2,
        constraints: {
          accumulator_slot: {
            kind: :shared_state_slot,
            methods: %w[add multiply],
            mode: :prescriptive,
            canonical_key: :value
          }
        }
      }
      g = described_class.new("calculator", log: log_path, role_profile: profile)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: "context[:value] = context.fetch(:value, 0) + args[0]; result = context[:value]"),
        program_payload(code: "context[:memory] = context.fetch(:memory, 0) * args[0]; result = context[:memory]")
      )

      expect_ok_outcome(g.add(2), value: 2)
      expect_ok_outcome(g.multiply(3), value: 0)

      entry = JSON.parse(File.readlines(log_path).last)
      expect(entry["active_role_profile_version"]).to eq(2)
      expect(entry["role_profile_compliance"]).to include("passed" => false)
      expect(entry["role_profile_correction_hint"]).to include("Use 'value'")
    end

    it "logs validation-stage attempt failures for guardrail recovery that later succeeds" do
      g = described_class.new("assistant", log: log_path, max_generation_attempts: 1, guardrail_recovery_budget: 1)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(
          code: <<~RUBY
            self.define_singleton_method(:oops) { 1 }
            result = :bad
          RUBY
        ),
        program_payload(code: "result = 42")
      )

      expect_ok_outcome(g.ask("latest news"), value: 42)

      entry = JSON.parse(File.readlines(log_path).first)
      expect(entry["guardrail_recovery_attempts"]).to eq(1)
      expect(entry["attempt_failures"]).to be_a(Array)
      expect(entry["attempt_failures"].length).to eq(1)
      expect(entry["attempt_failures"].first).to include(
        "attempt_id" => 1,
        "stage" => "validation",
        "error_class" => "Agent::ToolRegistryViolationError",
        "call_id" => entry["call_id"]
      )
      expect(entry["latest_failure_stage"]).to eq("validation")
      expect(entry["latest_failure_class"]).to eq("Agent::ToolRegistryViolationError")
      expect(entry["latest_failure_message"]).to include("singleton methods on Agent instances")
    end

    it "logs execution-stage attempt failures for fresh execution repair retries" do
      g = described_class.new("assistant", log: log_path, max_generation_attempts: 1)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(
          code: <<~RUBY
            response = nil
            response << "x"
            result = response
          RUBY
        ),
        program_payload(
          code: <<~RUBY
            response = +""
            response << "x"
            result = response
          RUBY
        )
      )

      expect_ok_outcome(g.ask("latest news"), value: "x")

      entry = JSON.parse(File.readlines(log_path).first)
      expect(entry["execution_repair_attempts"]).to eq(1)
      expect(entry["attempt_failures"]).to be_a(Array)
      expect(entry["attempt_failures"].length).to eq(1)
      expect(entry["attempt_failures"].first).to include(
        "attempt_id" => 1,
        "stage" => "execution",
        "error_class" => "Agent::ExecutionError",
        "call_id" => entry["call_id"]
      )
      expect(entry["latest_failure_stage"]).to eq("execution")
      expect(entry["latest_failure_class"]).to eq("Agent::ExecutionError")
      expect(entry["latest_failure_message"]).to include("undefined method")
    end

    it "logs outcome-policy attempt failures and truncates oversized failure messages" do
      g = described_class.new("assistant", log: log_path, max_generation_attempts: 1, fresh_outcome_repair_budget: 1)
      oversized_message = "x" * 500
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(
          code: <<~RUBY
            result = Agent::Outcome.error(
              error_type: "parse_failed",
              error_message: "#{oversized_message}",
              retriable: true
            )
          RUBY
        ),
        program_payload(code: 'result = Agent::Outcome.ok(data: "ok")')
      )

      expect_ok_outcome(g.ask("latest news"), value: { data: "ok" })

      entry = JSON.parse(File.readlines(log_path).first)
      expect(entry["outcome_repair_attempts"]).to eq(1)
      expect(entry["attempt_failures"]).to be_a(Array)
      expect(entry["attempt_failures"].length).to eq(1)
      expect(entry["attempt_failures"].first).to include(
        "attempt_id" => 1,
        "stage" => "outcome_policy",
        "error_class" => "Agent::OutcomeError",
        "call_id" => entry["call_id"]
      )
      expect(entry["latest_failure_stage"]).to eq("outcome_policy")
      expect(entry["latest_failure_class"]).to eq("Agent::OutcomeError")
      expect(entry["latest_failure_message"].length).to be <= 400
      expect(entry["latest_failure_message"]).to end_with("...")
    end

    it "records persisted artifact execution source fields" do
      Dir.mktmpdir("recurgent-log-artifact-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        seeder = described_class.new("calculator")
        stub_llm_response("result = 7")
        expect_ok_outcome(seeder.answer, value: 7)

        Agent.configure_runtime(toolstore_root: tmpdir)
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

    it "logs contract validation mismatch and error metadata for contract violations" do
      g = described_class.new(
        "web_fetcher",
        log: log_path,
        delegation_contract: {
          purpose: "fetch and extract content from urls",
          deliverable: { type: "object", required: ["body"] }
        }
      )
      stub_llm_response("result = { status: 200 }")

      outcome = g.fetch_url("https://example.com/feed")
      expect_error_outcome(outcome, type: "contract_violation", retriable: false)

      entry = JSON.parse(File.readlines(log_path).first)
      expect(entry["contract_validation_applied"]).to eq(true)
      expect(entry["contract_validation_passed"]).to eq(false)
      expect(entry["contract_validation_mismatch"]).to eq("missing_required_key")
      expect(entry["contract_validation_expected_keys"]).to eq(["body"])
      expect(entry["contract_validation_actual_keys"]).to include(":status")
      expect(entry["outcome_error_type"]).to eq("contract_violation")
      expect(entry["outcome_error_metadata"]).to include("mismatch" => "missing_required_key")
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
      expect(entry).to have_key("capability_pattern_evidence")
      expect(entry["context"]).to include("value" => 6)
      expect(entry["context"]["conversation_history"]).to be_a(Array)
      expect(entry["context"]["conversation_history"].length).to eq(1)
      expect(entry["outcome_value"]).to eq(6)
      expect(entry["system_prompt"]).to include("calculator")
      expect(entry["user_prompt"]).to include("increment")
    end

    it "normalizes non-utf8 debug values before JSON serialization" do
      g = described_class.new("calculator", log: log_path, debug: true)
      binary = [0xC3, 0x28].pack("C*").force_encoding(Encoding::ASCII_8BIT)

      value = g.send(:_debug_serializable_value, { "body" => binary })
      body = value.fetch("body")

      expect(body).to be_a(String)
      expect(body.encoding).to eq(Encoding::UTF_8)
      expect(body.valid_encoding?).to eq(true)
    end

    it "records capability patterns in logs and persists them for future sessions" do
      Dir.mktmpdir("recurgent-patterns-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        pattern_log = File.join(tmpdir, "patterns-log.jsonl")
        g = described_class.new("assistant", log: pattern_log, debug: true)
        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(
            code: <<~RUBY
              # require "rss"
              # Net::HTTP
              items = [{ "title" => "Story", "link" => "https://example.com/story" }]
              result = items.map { |item| { title: item["title"], link: item["link"] } }
            RUBY
          )
        )

        expect_ok_outcome(g.ask("latest headlines"), value: [{ title: "Story", link: "https://example.com/story" }])
        expect_ok_outcome(g.ask("latest headlines"), value: [{ title: "Story", link: "https://example.com/story" }])
        entry = JSON.parse(File.readlines(pattern_log).last)
        expect(entry["capability_patterns"]).to include("rss_parse", "http_fetch", "news_headline_extract")
        expect(entry.fetch("capability_pattern_evidence", {})).to have_key("rss_parse")

        pattern_path = File.join(tmpdir, "patterns.json")
        expect(File).to exist(pattern_path)
        patterns_store = JSON.parse(File.read(pattern_path))
        events = patterns_store.dig("roles", "assistant", "events")
        expect(events).not_to be_nil
        expect(events.last["method_name"]).to eq("ask")
        expect(events.last["capability_patterns"]).to include("rss_parse", "http_fetch", "news_headline_extract")

        Agent.configure_runtime(toolstore_root: tmpdir)
        warm = described_class.new("assistant")
        warm_prompt = warm.send(:_build_user_prompt, "ask", [], {}, call_context: { depth: 0 })
        expect(warm_prompt).to include("<recent_patterns>")
        expect(warm_prompt).to include("seen 2 of last 2 ask calls")
        expect(warm_prompt).to include("ask calls")
      end
    end

    it "marks repeated top-level ask calls with near-identical capabilities as user_correction" do
      Dir.mktmpdir("recurgent-user-correction-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        correction_log = File.join(tmpdir, "correction-log.jsonl")
        g = described_class.new("assistant", log: correction_log, debug: true)
        ask_code = <<~RUBY
          # Net::HTTP
          items = [{ "title" => "Story", "link" => "https://example.com/story" }]
          result = items.map { |item| { title: item["title"], link: item["link"] } }
        RUBY

        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(code: ask_code),
          program_payload(code: ask_code)
        )

        expected_headlines = [{ title: "Story", link: "https://example.com/story" }]
        expect_ok_outcome(g.ask("what movies are playing?"), value: expected_headlines)
        expect_ok_outcome(g.ask("try again, what movies are playing?"), value: expected_headlines)

        entries = File.readlines(correction_log).map { |line| JSON.parse(line) }
        expect(entries.length).to eq(2)
        expect(entries.last["user_correction_detected"]).to eq(true)
        expect(entries.last["user_correction_signal"]).to eq("temporal_reask")
        expect(entries.last["user_correction_reference_call_id"]).to eq(entries.first["call_id"])

        pattern_store = JSON.parse(File.read(File.join(tmpdir, "patterns.json")))
        events = pattern_store.dig("roles", "assistant", "events")
        expect(events.length).to eq(2)
        expect(events.last.dig("user_correction", "detected")).to eq(true)
        expect(events.last.dig("user_correction", "signal")).to eq("temporal_reask")
        expect(events.last.dig("user_correction", "correction_of_call_id")).to eq(events.first["call_id"])
      end
    end

    it "applies temporal re-ask user_correction detection to any repeated top-level method" do
      Dir.mktmpdir("recurgent-user-correction-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        correction_log = File.join(tmpdir, "correction-generic-log.jsonl")
        g = described_class.new("assistant", log: correction_log, debug: true)
        lookup_code = <<~RUBY
          # Net::HTTP
          seed_query = "seed-query"
          items = [{ "title" => "Story", "link" => "https://example.com/story" }]
          result = items.map { |item| { title: item["title"], link: item["link"] } }
        RUBY

        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(code: lookup_code),
          program_payload(code: lookup_code)
        )

        expected_headlines = [{ title: "Story", link: "https://example.com/story" }]
        expect_ok_outcome(g.lookup("seed-query"), value: expected_headlines)
        expect_ok_outcome(g.lookup("followup-query"), value: expected_headlines)

        entries = File.readlines(correction_log).map { |line| JSON.parse(line) }
        expect(entries.length).to eq(2)
        expect(entries.last["method"]).to eq("lookup")
        expect(entries.last["user_correction_detected"]).to eq(true)
        expect(entries.last["user_correction_signal"]).to eq("temporal_reask")
        expect(entries.last["user_correction_reference_call_id"]).to eq(entries.first["call_id"])
      end
    end

    it "does not mark user_correction when repeated ask calls shift capability patterns" do
      Dir.mktmpdir("recurgent-user-correction-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        correction_log = File.join(tmpdir, "correction-shift-log.jsonl")
        g = described_class.new("assistant", log: correction_log, debug: true)
        first_code = <<~RUBY
          # Net::HTTP
          items = [{ "title" => "Story", "link" => "https://example.com/story" }]
          result = items.map { |item| { title: item["title"], link: item["link"] } }
        RUBY
        shifted_code = <<~RUBY
          # REXML::Document
          records = [{ "name" => "Story" }]
          result = records.map { |record| record["name"] }
        RUBY

        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(code: first_code),
          program_payload(code: shifted_code)
        )

        expect_ok_outcome(g.ask("what movies are playing?"), value: [{ title: "Story", link: "https://example.com/story" }])
        expect_ok_outcome(g.ask("what movies are in theaters now?"), value: ["Story"])

        entries = File.readlines(correction_log).map { |line| JSON.parse(line) }
        expect(entries.last["user_correction_detected"]).to eq(false)
        expect(entries.last["user_correction_signal"]).to be_nil
        expect(entries.last["user_correction_reference_call_id"]).to be_nil

        pattern_store = JSON.parse(File.read(File.join(tmpdir, "patterns.json")))
        events = pattern_store.dig("roles", "assistant", "events")
        expect(events.last["user_correction"]).to be_nil
      end
    end

    it "marks repeated top-level calls without delegation or capability patterns as temporal_reask_no_tooling" do
      Dir.mktmpdir("recurgent-user-correction-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        correction_log = File.join(tmpdir, "correction-no-tooling-log.jsonl")
        g = described_class.new("assistant", log: correction_log, debug: true)
        conversational_code = <<~RUBY
          context[:conversation_history] ||= []
          context[:conversation_history] << { role: "user", message: args.first.to_s }
          result = "I don't have enough data yet."
        RUBY

        allow(mock_provider).to receive(:generate_program).and_return(
          program_payload(code: conversational_code),
          program_payload(code: conversational_code)
        )

        expect_ok_outcome(g.ask("what movies are playing?"), value: "I don't have enough data yet.")
        expect_ok_outcome(g.ask("try again, what movies are playing?"), value: "I don't have enough data yet.")

        entries = File.readlines(correction_log).map { |line| JSON.parse(line) }
        expect(entries.length).to eq(2)
        expect(entries.map { |entry| entry["conversation_history_size"] }).to eq([1, 2])
        expect(entries.last["user_correction_detected"]).to eq(true)
        expect(entries.last["user_correction_signal"]).to eq("temporal_reask_no_tooling")
        expect(entries.last["user_correction_reference_call_id"]).to eq(entries.first["call_id"])

        history = g.runtime_context[:conversation_history]
        expect(history).to all(
          include(
            :method_name,
            :args,
            :kwargs,
            :outcome_summary
          )
        )
        expect(history).to all(satisfy { |record| !record.key?(:message) })

        pattern_store = JSON.parse(File.read(File.join(tmpdir, "patterns.json")))
        events = pattern_store.dig("roles", "assistant", "events")
        expect(events.length).to eq(2)
        expect(events.last["had_delegated_calls"]).to eq(false)
        expect(events.last.dig("user_correction", "signal")).to eq("temporal_reask_no_tooling")
      end
    end

    it "logs conversation history append and usage telemetry fields" do
      g = described_class.new("assistant", log: log_path, debug: true)
      stub_llm_response(<<~RUBY)
        history = context[:conversation_history] || []
        result = history.map { |entry| entry[:method_name] || entry["method_name"] }
      RUBY

      expect_ok_outcome(g.ask("hello"), value: [])

      entry = JSON.parse(File.readlines(log_path).first)
      expect(entry["history_record_appended"]).to eq(true)
      expect(entry["conversation_history_size"]).to eq(1)
      expect(entry["history_access_detected"]).to eq(true)
      expect(entry["history_query_patterns"]).to include("map")
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
end
