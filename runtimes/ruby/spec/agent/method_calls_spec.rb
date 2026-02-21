# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "timeout"
require_relative "../support/agent_spec_shared_context"

RSpec.describe Agent do
  include_context "agent spec context"
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

    it "returns context-backed readers without provider generation" do
      g = described_class.new("calculator")
      g.memory = 5
      stub_llm_response("result = context[:memory]")

      expect_ok_outcome(g.memory, value: 5)
      expect(mock_provider).not_to have_received(:generate_program)
    end

    it "supports memory alias as a local reference to context in generated code" do
      g = described_class.new("calculator")
      stub_llm_response("memory[:value] = memory.fetch(:value, 0) + 2; result = memory[:value]")

      expect_ok_outcome(g.bump, value: 2)
      expect(g.runtime_context[:value]).to eq(2)
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

    it "retries fresh generation once after execution error with runtime feedback" do
      g = described_class.new("assistant", max_generation_attempts: 1)
      prompts = []
      allow(mock_provider).to receive(:generate_program) do |payload|
        prompts << payload.fetch(:user_prompt, "")
        if prompts.length == 1
          program_payload(code: 'result = nil; result << "x"')
        else
          program_payload(code: 'buffer = +""; buffer << "x"; result = buffer')
        end
      end

      outcome = g.ask("say x")
      expect_ok_outcome(outcome, value: "x")
      expect(prompts.length).to eq(2)
      expect(prompts.last).to include("<execution_failure_feedback>")
      expect(prompts.last).to include("Initialize accumulators before append operations")
    end

    it "returns execution error when fresh execution repair budget is exhausted" do
      g = described_class.new("assistant", max_generation_attempts: 1)
      prompts = []
      allow(mock_provider).to receive(:generate_program) do |payload|
        prompts << payload.fetch(:user_prompt, "")
        program_payload(code: 'result = nil; result << "x"')
      end

      outcome = g.ask("say x")
      expect_error_outcome(outcome, type: "execution", retriable: false)
      expect(prompts.length).to eq(2)
      expect(prompts.last).to include("<execution_failure_feedback>")
    end

    it "retries fresh generation once after retriable error outcome with runtime feedback" do
      g = described_class.new("assistant", max_generation_attempts: 1, fresh_outcome_repair_budget: 1)
      prompts = []
      allow(mock_provider).to receive(:generate_program) do |payload|
        prompts << payload.fetch(:user_prompt, "")
        if prompts.length == 1
          program_payload(
            code: <<~RUBY
              result = Agent::Outcome.error(
                error_type: "fetch_failed",
                error_message: "Exception during fetch: NoMethodError - undefined method 'scan' for an instance of Agent::Outcome",
                retriable: true
              )
            RUBY
          )
        else
          program_payload(code: 'result = "recovered"')
        end
      end

      outcome = g.ask("latest nyt")
      expect_ok_outcome(outcome, value: "recovered")
      expect(prompts.length).to eq(2)
      expect(prompts.last).to include("<outcome_failure_feedback>")
      expect(prompts.last).to include("Unwrap Outcome values before parsing")
    end

    it "returns outcome_repair_retry_exhausted when fresh outcome repair budget is exhausted" do
      g = described_class.new("assistant", max_generation_attempts: 1, fresh_outcome_repair_budget: 1)
      prompts = []
      allow(mock_provider).to receive(:generate_program) do |payload|
        prompts << payload.fetch(:user_prompt, "")
        program_payload(
          code: <<~RUBY
            result = Agent::Outcome.error(
              error_type: "fetch_failed",
              error_message: "Exception during fetch: NoMethodError - undefined method 'scan' for an instance of Agent::Outcome",
              retriable: true
            )
          RUBY
        )
      end

      outcome = g.ask("latest nyt")
      expect_error_outcome(outcome, type: "outcome_repair_retry_exhausted", retriable: false)
      expect(prompts.length).to eq(2)
      expect(prompts.last).to include("<outcome_failure_feedback>")
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

    it "keeps generated method definitions isolated to one execution attempt" do
      g = described_class.new("assistant")
      leaked_name = :leaked_helper_from_generated_code
      expect(g.respond_to?(leaked_name)).to eq(false)

      stub_llm_response(<<~RUBY)
        def leaked_helper_from_generated_code
          41
        end
        result = leaked_helper_from_generated_code
      RUBY

      expect_ok_outcome(g.ask("compute"), value: 41)
      expect(g.respond_to?(leaked_name)).to eq(false)
      expect(described_class.new("assistant").respond_to?(leaked_name)).to eq(false)
    end

    it "supports Agent::Outcome.call as a tolerant success constructor" do
      g = described_class.new("assistant")
      stub_llm_response("result = Agent::Outcome.call(42)")

      outcome = g.answer
      expect_ok_outcome(outcome, value: 42)
      expect(outcome.tool_role).to eq("assistant")
      expect(outcome.method_name).to eq("answer")
    end

    it "supports success? as a tolerant alias for ok?" do
      g = described_class.new("assistant")
      stub_llm_response("result = Agent::Outcome.ok(42).success?")

      expect_ok_outcome(g.answer, value: true)
    end

    it "supports failure? as a tolerant alias for error?" do
      g = described_class.new("assistant")
      stub_llm_response('result = Agent::Outcome.error("x", "boom").failure?')

      expect_ok_outcome(g.answer, value: true)
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

    it "merges kwargs into positional hash value in Agent::Outcome.ok" do
      g = described_class.new("assistant")
      stub_llm_response(
        <<~RUBY
          result = Agent::Outcome.ok(
            { data: [{ title: "Story" }] },
            provenance: {
              sources: [
                {
                  uri: "https://example.com/feed",
                  fetched_at: "2026-02-16T00:00:00Z",
                  retrieval_tool: "web_fetcher",
                  retrieval_mode: "live"
                }
              ]
            }
          )
        RUBY
      )

      expect_ok_outcome(
        g.fetch,
        value: {
          data: [{ title: "Story" }],
          provenance: {
            sources: [
              {
                uri: "https://example.com/feed",
                fetched_at: "2026-02-16T00:00:00Z",
                retrieval_tool: "web_fetcher",
                retrieval_mode: "live"
              }
            ]
          }
        }
      )
    end

    it "merges kwargs into value: hash in Agent::Outcome.ok" do
      g = described_class.new("assistant")
      stub_llm_response(
        <<~RUBY
          result = Agent::Outcome.ok(
            value: { data: [{ title: "Story" }] },
            provenance: {
              sources: [
                {
                  uri: "https://example.com/feed",
                  fetched_at: "2026-02-16T00:00:00Z",
                  retrieval_tool: "web_fetcher",
                  retrieval_mode: "live"
                }
              ]
            }
          )
        RUBY
      )

      expect_ok_outcome(
        g.fetch,
        value: {
          data: [{ title: "Story" }],
          provenance: {
            sources: [
              {
                uri: "https://example.com/feed",
                fetched_at: "2026-02-16T00:00:00Z",
                retrieval_tool: "web_fetcher",
                retrieval_mode: "live"
              }
            ]
          }
        }
      )
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

    it "returns guardrail_retry_exhausted when guardrail retries are exhausted on executable pseudo-tools in context[:tools]" do
      g = described_class.new("assistant")
      stub_llm_response(
        <<~RUBY
          context[:tools] ||= {}
          context[:tools]["bad_fetcher"] = {
            purpose: "inline pseudo tool",
            fetch_latest: -> { "not allowed" }
          }
          result = "done"
        RUBY
      )

      outcome = g.ask("latest news")
      expect_error_outcome(outcome, type: "guardrail_retry_exhausted", retriable: false)
      expect(outcome.metadata).to include(
        guardrail_recovery_attempts: 2,
        last_violation_type: "tool_registry_violation"
      )
    end

    it "returns guardrail_retry_exhausted when generated code repeatedly defines singleton methods on delegated tools" do
      g = described_class.new("assistant")
      stub_llm_response(
        <<~RUBY
          fetcher = delegate("web_fetcher", purpose: "fetch content")
          fetcher.define_singleton_method(:fetch_latest) { Agent::Outcome.ok({}) }
          result = "done"
        RUBY
      )

      outcome = g.ask("latest news")
      expect_error_outcome(outcome, type: "guardrail_retry_exhausted", retriable: false)
      expect(outcome.error_message).to eq("This request couldn't be completed after multiple attempts.")
      expect(outcome.metadata).to include(
        normalized: true,
        normalization_policy: "guardrail_exhaustion_boundary_v1",
        guardrail_class: "recoverable_guardrail",
        guardrail_subtype: "singleton_method_mutation",
        guardrail_recovery_attempts: 2,
        last_violation_type: "tool_registry_violation"
      )
      expect(outcome.metadata[:last_violation_subtype]).to eq("singleton_method_mutation")
    end

    it "returns guardrail_retry_exhausted when generated code treats context[:tools] as an array of entries" do
      g = described_class.new("assistant")
      stub_llm_response(
        <<~RUBY
          web_fetcher_available = context[:tools]&.any? { |t| t.is_a?(Hash) && (t[:name] == "web_fetcher" || t["name"] == "web_fetcher") }
          result = web_fetcher_available
        RUBY
      )

      outcome = g.ask("latest news")
      expect_error_outcome(outcome, type: "guardrail_retry_exhausted", retriable: false)
      expect(outcome.metadata).to include(
        guardrail_recovery_attempts: 2,
        last_violation_type: "tool_registry_violation"
      )
    end

    it "returns guardrail_retry_exhausted when generated code returns hardcoded fallback as Outcome.ok in external-fetch flows" do
      g = described_class.new("assistant")
      stub_llm_response(
        <<~RUBY
          require 'net/http'
          fallback_movies = [{ title: "Example" }]
          result = Agent::Outcome.ok(fallback_movies)
        RUBY
      )

      outcome = g.ask("latest movies")
      expect_error_outcome(outcome, type: "guardrail_retry_exhausted", retriable: false)
      expect(outcome.metadata).to include(
        guardrail_recovery_attempts: 2,
        last_violation_type: "tool_registry_violation"
      )
    end

    it "returns guardrail_retry_exhausted when external-data success omits provenance metadata" do
      g = described_class.new("assistant")
      stub_llm_response(
        <<~RUBY
          require 'net/http'
          result = Agent::Outcome.ok(
            data: [{ title: "Example Story" }]
          )
        RUBY
      )

      outcome = g.ask("latest headlines")
      expect_error_outcome(outcome, type: "guardrail_retry_exhausted", retriable: false)
      expect(outcome.metadata).to include(
        guardrail_recovery_attempts: 2,
        last_violation_type: "tool_registry_violation"
      )
      expect(outcome.metadata[:last_violation_subtype]).to eq("missing_external_provenance")
    end

    it "does not normalize exhausted guardrail errors for depth-1 tool outcomes" do
      g = described_class.new("assistant")
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(
          code: <<~RUBY
            child = delegate("child_tool", purpose: "do guarded work")
            outcome = child.run
            result = outcome
          RUBY
        ),
        program_payload(
          code: <<~RUBY
            self.define_singleton_method(:oops) { 1 }
            result = :bad
          RUBY
        ),
        program_payload(
          code: <<~RUBY
            self.define_singleton_method(:oops) { 1 }
            result = :bad
          RUBY
        )
      )

      outcome = g.ask("run child tool")
      expect_error_outcome(outcome, type: "guardrail_retry_exhausted", retriable: false)
      expect(outcome.error_message).to include("Recoverable guardrail retries exhausted for child_tool.run")
      expect(outcome.metadata[:normalized]).to be_nil
      expect(outcome.metadata[:normalization_policy]).to be_nil
      expect(outcome.metadata[:last_violation_subtype]).to eq("singleton_method_mutation")
    end

    it "allows external-data success with provenance metadata" do
      g = described_class.new("assistant")
      stub_llm_response(
        <<~RUBY
          require 'net/http'
          result = Agent::Outcome.ok(
            data: [{ title: "Example Story" }],
            provenance: {
              sources: [
                {
                  uri: "https://example.com/feed",
                  fetched_at: "2026-02-16T00:00:00Z",
                  retrieval_tool: "web_fetcher",
                  retrieval_mode: "live"
                }
              ]
            }
          )
        RUBY
      )

      expect_ok_outcome(
        g.ask("latest headlines"),
        value: {
          data: [{ title: "Example Story" }],
          provenance: {
            sources: [
              {
                uri: "https://example.com/feed",
                fetched_at: "2026-02-16T00:00:00Z",
                retrieval_tool: "web_fetcher",
                retrieval_mode: "live"
              }
            ]
          }
        }
      )
    end

    it "recovers from a guardrail violation on the next regeneration attempt" do
      g = described_class.new("assistant", max_generation_attempts: 1, guardrail_recovery_budget: 1)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(
          code: <<~RUBY
            fetcher = delegate("web_fetcher", purpose: "fetch content")
            fetcher.define_singleton_method(:fetch_latest) { Agent::Outcome.ok({}) }
            result = "done"
          RUBY
        ),
        program_payload(code: "result = 42")
      )

      expect_ok_outcome(g.ask("latest news"), value: 42)
      expect(mock_provider).to have_received(:generate_program).twice
    end

    it "recovers from context[:tools] shape misuse on the next regeneration attempt" do
      g = described_class.new("assistant", max_generation_attempts: 1, guardrail_recovery_budget: 1)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(
          code: <<~RUBY
            web_fetcher_available = context[:tools]&.any? { |t| t.is_a?(Hash) && t[:name] == "web_fetcher" }
            result = web_fetcher_available
          RUBY
        ),
        program_payload(
          code: <<~RUBY
            registry = context[:tools] || {}
            result = registry.key?("web_fetcher")
          RUBY
        )
      )

      expect_ok_outcome(g.ask("latest news"), value: false)
      expect(mock_provider).to have_received(:generate_program).twice
    end

    it "recovers from hardcoded external fallback success on the next regeneration attempt" do
      g = described_class.new("assistant", max_generation_attempts: 1, guardrail_recovery_budget: 1)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(
          code: <<~RUBY
            require 'net/http'
            fallback_movies = [{ title: "Example" }]
            result = Agent::Outcome.ok(fallback_movies)
          RUBY
        ),
        program_payload(
          code: <<~RUBY
            result = Agent::Outcome.error(
              error_type: "low_utility",
              error_message: "Could not fetch live movie data",
              retriable: false
            )
          RUBY
        )
      )

      expect_error_outcome(g.ask("latest movies"), type: "low_utility", retriable: false)
      expect(mock_provider).to have_received(:generate_program).twice
    end

    it "recovers from missing provenance on external-data success in the next regeneration attempt" do
      g = described_class.new("assistant", max_generation_attempts: 1, guardrail_recovery_budget: 1)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(
          code: <<~RUBY
            require 'net/http'
            result = Agent::Outcome.ok(data: [{ title: "Story" }])
          RUBY
        ),
        program_payload(
          code: <<~RUBY
            result = Agent::Outcome.ok(
              data: [{ title: "Story" }],
              provenance: {
                sources: [
                  {
                    uri: "https://example.com/feed",
                    fetched_at: "2026-02-16T00:00:00Z",
                    retrieval_tool: "web_fetcher",
                    retrieval_mode: "live"
                  }
                ]
              }
            )
          RUBY
        )
      )

      outcome = g.ask("latest headlines")
      expect_ok_outcome(
        outcome,
        value: {
          data: [{ title: "Story" }],
          provenance: {
            sources: [
              {
                uri: "https://example.com/feed",
                fetched_at: "2026-02-16T00:00:00Z",
                retrieval_tool: "web_fetcher",
                retrieval_mode: "live"
              }
            ]
          }
        }
      )
      expect(mock_provider).to have_received(:generate_program).twice
    end

    it "appends one conversation history record for one logical call across guardrail retries" do
      g = described_class.new("assistant", max_generation_attempts: 1, guardrail_recovery_budget: 1)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(
          code: <<~RUBY
            fetcher = delegate("web_fetcher", purpose: "fetch content")
            fetcher.define_singleton_method(:fetch_latest) { Agent::Outcome.ok({}) }
            result = "done"
          RUBY
        ),
        program_payload(code: "result = 42")
      )

      expect_ok_outcome(g.ask("latest news"), value: 42)
      history = g.runtime_context[:conversation_history]
      expect(history).to be_a(Array)
      expect(history.size).to eq(1)
      expect(history.first).to include(
        speaker: "user",
        method_name: "ask"
      )
      expect(history.first.fetch(:outcome_summary)).to include(
        status: "ok",
        ok: true
      )
    end

    it "rolls back attempt-local context mutations before guardrail retry" do
      g = described_class.new("assistant", max_generation_attempts: 1, guardrail_recovery_budget: 1)
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(
          code: <<~RUBY
            context[:note] = "polluted"
            context[:tools] ||= {}
            context[:tools]["bad_fetcher"] = { fetch_latest: -> { "bad" } }
            result = "bad"
          RUBY
        ),
        program_payload(code: "result = { note: context[:note], tools: context[:tools] }")
      )

      outcome = g.ask("latest news")
      expect_ok_outcome(outcome, value: { note: nil, tools: nil })
    end

    it "coerces malformed conversation_history to an array before appending canonical record" do
      g = described_class.new("assistant")
      g.remember(conversation_history: "malformed")
      stub_llm_response("result = args.first")

      expect_ok_outcome(g.echo("hello"), value: "hello")
      history = g.runtime_context[:conversation_history]
      expect(history).to be_a(Array)
      expect(history.size).to eq(1)
      expect(history.first).to include(
        call_id: be_a(String),
        timestamp: be_a(String),
        speaker: "user",
        method_name: "echo",
        args: ["hello"],
        kwargs: {}
      )
      expect(history.first.fetch(:outcome_summary)).to include(
        status: "ok",
        ok: true,
        error_type: nil,
        retriable: false,
        value_class: "String"
      )
    end

    it "stores compact provenance refs in conversation history outcome summaries for external-data success" do
      g = described_class.new("assistant")
      stub_llm_response(
        <<~RUBY
          result = Agent::Outcome.ok(
            data: [{ title: "Story" }],
            provenance: {
              sources: [
                {
                  uri: "https://news.example.com/feed",
                  fetched_at: "2026-02-16T00:00:00Z",
                  retrieval_tool: "web_fetcher",
                  retrieval_mode: "live"
                },
                {
                  uri: "https://news.example.com/backup",
                  fetched_at: "2026-02-16T00:00:01Z",
                  retrieval_tool: "web_fetcher",
                  retrieval_mode: "cached"
                }
              ]
            }
          )
        RUBY
      )

      expect_ok_outcome(
        g.ask("latest stories"),
        value: {
          data: [{ title: "Story" }],
          provenance: {
            sources: [
              {
                uri: "https://news.example.com/feed",
                fetched_at: "2026-02-16T00:00:00Z",
                retrieval_tool: "web_fetcher",
                retrieval_mode: "live"
              },
              {
                uri: "https://news.example.com/backup",
                fetched_at: "2026-02-16T00:00:01Z",
                retrieval_tool: "web_fetcher",
                retrieval_mode: "cached"
              }
            ]
          }
        }
      )
      summary = g.runtime_context.fetch(:conversation_history).last.fetch(:outcome_summary)
      expect(summary).to include(
        status: "ok",
        source_count: 2,
        primary_uri: "https://news.example.com/feed",
        retrieval_mode: "live"
      )
    end

    it "stores content continuity refs in conversation history summaries for successful outcomes" do
      g = described_class.new("assistant")
      stub_llm_response(
        <<~RUBY
          result = {
            message: "hello",
            items: [1, 2, 3]
          }
        RUBY
      )

      expect_ok_outcome(g.ask("hello"), value: { message: "hello", items: [1, 2, 3] })
      summary = g.runtime_context.fetch(:conversation_history).last.fetch(:outcome_summary)
      expect(summary[:content_ref]).to match(/\Acontent:/)
      expect(summary[:content_kind]).to eq("object")
      expect(summary[:content_bytes]).to be_a(Integer)
      expect(summary[:content_bytes]).to be > 0
      expect(summary[:content_digest]).to match(/\Asha256:/)
    end

    it "does not store depth>=1 content refs by default when nested capture is disabled" do
      g = described_class.new("assistant")
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(
          code: <<~RUBY
            worker = delegate("echo_worker")
            worker.ask("nested")
            nested_summary = worker.runtime_context.fetch(:conversation_history).last.fetch(:outcome_summary)
            result = nested_summary[:content_ref] || nested_summary["content_ref"]
          RUBY
        ),
        program_payload(code: 'result = "nested response"')
      )

      expect_ok_outcome(g.ask("run nested"), value: nil)
    end

    it "stores depth>=1 content refs when nested capture is explicitly enabled in runtime config" do
      Agent.configure_runtime(toolstore_root: runtime_toolstore_root, content_store_nested_capture_enabled: true)
      g = described_class.new("assistant")
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(
          code: <<~RUBY
            worker = delegate("echo_worker")
            worker.ask("nested")
            nested_summary = worker.runtime_context.fetch(:conversation_history).last.fetch(:outcome_summary)
            result = nested_summary[:content_ref] || nested_summary["content_ref"]
          RUBY
        ),
        program_payload(code: 'result = "nested response"')
      )

      outcome = g.ask("run nested")
      expect(outcome).to be_ok
      expect(outcome.value).to match(/\Acontent:/)
    end

    it "allows generated code to resolve prior payloads via content(ref)" do
      g = described_class.new("assistant")
      allow(mock_provider).to receive(:generate_program).and_return(
        program_payload(code: 'result = { "snippet" => "QuickSort implementation in Smalltalk" }'),
        program_payload(
          code: <<~RUBY
            history = context[:conversation_history] || []
            summary = history.last[:outcome_summary] || history.last["outcome_summary"] || {}
            ref = summary[:content_ref] || summary["content_ref"]
            result = content(ref)
          RUBY
        )
      )

      expect_ok_outcome(
        g.ask("write quicksort in smalltalk"),
        value: { "snippet" => "QuickSort implementation in Smalltalk" }
      )
      expect_ok_outcome(
        g.ask("format that in markdown"),
        value: { "snippet" => "QuickSort implementation in Smalltalk" }
      )
    end

    it "supports typed content_ref_not_found handling when content(ref) misses" do
      g = described_class.new("assistant")
      stub_llm_response(
        <<~RUBY
          payload = content("content:missing")
          if payload.nil?
            result = Agent::Outcome.error(
              error_type: "content_ref_not_found",
              error_message: "Referenced content is unavailable.",
              retriable: false
            )
          else
            result = payload
          end
        RUBY
      )

      expect_error_outcome(g.ask("format previous response"), type: "content_ref_not_found", retriable: false)
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
end
