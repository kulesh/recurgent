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
                       .and(including("context[:conversation_history]"))
                       .and(including("External-data success invariant"))
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

    it "includes conversation history count and access hint without preloading records in user prompt" do
      g = described_class.new("assistant")
      g.remember(
        conversation_history: [
          { call_id: "c1", speaker: "user", method_name: "ask", outcome_summary: { status: "ok" } },
          { call_id: "c2", speaker: "user", method_name: "ask", outcome_summary: { status: "ok" } },
          { call_id: "c3", speaker: "user", method_name: "ask", outcome_summary: { status: "ok" } },
          { call_id: "c4", speaker: "user", method_name: "ask", outcome_summary: { status: "error", error_type: "low_utility" } }
        ]
      )
      expect_llm_call_with(
        code: "result = nil",
        user_prompt: satisfy do |prompt|
          history_access_hint = "History contents are available in context[:conversation_history]. " \
                                "Inspect via generated Ruby code when needed; prompt does not preload records."
          schema_hint = "Each record includes: call_id, timestamp, speaker, method_name, args, kwargs, outcome_summary."
          source_refs_hint = "When present, outcome_summary may include compact source refs: source_count, primary_uri, retrieval_mode."
          canonical_hint = "Prefer canonical fields (`record[:args]`, `record[:method_name]`, " \
                           "`record[:outcome_summary]`); do not rely on ad hoc keys."
          source_protocol_hint = "If current ask is about source/provenance/how data was obtained:"
          prompt.include?("<conversation_history>") &&
            prompt.include?("<record_count>4</record_count>") &&
            prompt.include?(history_access_hint) &&
            prompt.include?(schema_hint) &&
            prompt.include?(source_refs_hint) &&
            prompt.include?(canonical_hint) &&
            prompt.include?(source_protocol_hint) &&
            !prompt.include?("<recent_records>") &&
            !prompt.include?("c2") &&
            !prompt.include?("c3") &&
            !prompt.include?("c4") &&
            !prompt.include?("c1")
        end
      )

      g.ask("latest")
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

    it "includes known tool method names in known-tools prompt rendering" do
      g = described_class.new("planner")
      g.remember(
        tools: {
          "web_fetcher" => {
            purpose: "fetch and extract content from urls",
            methods: %w[fetch_url fetch]
          }
        }
      )

      prompt = g.send(:_known_tools_prompt)
      expect(prompt).to include("- web_fetcher: fetch and extract content from urls")
      expect(prompt).to include("methods: [fetch_url, fetch]")
    end

    it "includes inferred capability tags in known-tools prompt rendering" do
      g = described_class.new("planner")
      g.remember(
        tools: {
          "movie_finder" => {
            purpose: "fetch and parse movie listings from theater/movie websites",
            methods: ["fetch_listings"]
          }
        }
      )

      prompt = g.send(:_known_tools_prompt)
      expect(prompt).to include("- movie_finder: fetch and parse movie listings from theater/movie websites")
      expect(prompt).to include("capabilities: [http_fetch, html_extract, movie_listings]")
    end

    it "backfills inferred capabilities into in-memory tool metadata snapshot for prompt-time matching" do
      g = described_class.new("planner")
      g.remember(
        tools: {
          "web_fetcher" => {
            purpose: "fetch content from HTTP/HTTPS URLs with redirect handling",
            methods: ["fetch_url"]
          }
        }
      )

      snapshot = g.send(:_known_tools_snapshot)
      snapshot_capabilities = snapshot.dig("web_fetcher", :capabilities) || snapshot.dig("web_fetcher", "capabilities")
      memory_capabilities = g.memory.dig(:tools, "web_fetcher", :capabilities) ||
                            g.memory.dig(:tools, "web_fetcher", "capabilities")
      expect(snapshot_capabilities).to include("http_fetch")
      expect(memory_capabilities).to include("http_fetch")
    end

    it "merges persisted method metadata into known-tools prompt when memory snapshot is stale" do
      Dir.mktmpdir("recurgent-known-tools-") do |tmpdir|
        Agent.configure_runtime(toolstore_root: tmpdir)
        registry_path = File.join(tmpdir, "registry.json")
        File.write(
          registry_path,
          JSON.generate(
            schema_version: Agent::TOOLSTORE_SCHEMA_VERSION,
            tools: {
              "web_fetcher" => {
                purpose: "fetch and extract content from urls",
                methods: ["fetch_url"]
              }
            }
          )
        )

        g = described_class.new("planner")
        g.remember(
          tools: {
            "web_fetcher" => {
              purpose: "fetch and extract content from urls",
              methods: []
            }
          }
        )

        prompt = g.send(:_known_tools_prompt)
        expect(prompt).to include("- web_fetcher: fetch and extract content from urls")
        expect(prompt).to include("methods: [fetch_url]")
      end
    end

    it "injects interface overlap observations when a tool has multiple methods" do
      g = described_class.new("planner")
      g.remember(
        tools: {
          "web_fetcher" => {
            purpose: "fetch and extract content from urls",
            methods: %w[fetch fetch_url]
          }
        }
      )

      prompt = g.send(:_build_user_prompt, "ask", [], {}, call_context: { depth: 0 })
      expect(prompt).to include("<interface_overlap_observations>")
      expect(prompt).to include("- web_fetcher has multiple methods for similar capability: [fetch, fetch_url]")
      expect(prompt).to include("Consider consolidating to one canonical method when behavior overlaps.")
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
          failure_policy: { on_error: "fallback" },
          intent_signature: "ask: build pdf from report"
        }
      )
      expect_llm_call_with(
        code: "result = nil",
        system_prompt: a_string_including("Tool Builder Delegation Contract")
                       .and(including("generate a PDF file"))
                       .and(including('intent_signature: "ask: build pdf from report"')),
        user_prompt: a_string_including("<invocation>")
                     .and(including("<active_contract>"))
                     .and(including("application/pdf"))
                     .and(including("<intent_signature>\"ask: build pdf from report\"</intent_signature>"))
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

    it "injects recent pattern memory for depth-0 dynamic calls" do
      g = described_class.new("assistant")
      g.remember(
        tools: {
          "web_fetcher" => { purpose: "fetch and extract content from urls" }
        }
      )

      3.times do |index|
        g.send(
          :_pattern_memory_append_event,
          role: "assistant",
          event: {
            "timestamp" => "2026-02-15T07:00:0#{index}.000Z",
            "role" => "assistant",
            "method_name" => "ask",
            "capability_patterns" => %w[http_fetch rss_parse],
            "outcome_status" => "ok",
            "error_type" => nil
          }
        )
      end

      prompt = g.send(:_build_user_prompt, "ask", [], {}, call_context: { depth: 0 })
      expect(prompt).to include("<recent_patterns>")
      expect(prompt).to include("http_fetch: seen 3 of last 3 ask calls, tool_present=true(web_fetcher)")
      expect(prompt).to include("rss_parse: seen 3 of last 3 ask calls, tool_present=false")
      expect(prompt).to include("<promotion_nudge>")
    end

    it "does not inject recent pattern memory for non-depth-0 or non-dynamic calls" do
      g = described_class.new("assistant")

      2.times do |index|
        g.send(
          :_pattern_memory_append_event,
          role: "assistant",
          event: {
            "timestamp" => "2026-02-15T07:00:0#{index}.000Z",
            "role" => "assistant",
            "method_name" => "ask",
            "capability_patterns" => ["http_fetch"],
            "outcome_status" => "ok",
            "error_type" => nil
          }
        )
      end

      depth_one_prompt = g.send(:_build_user_prompt, "ask", [], {}, call_context: { depth: 1 })
      static_prompt = g.send(:_build_user_prompt, "parse", [], {}, call_context: { depth: 0 })
      expect(depth_one_prompt).not_to include("<recent_patterns>")
      expect(static_prompt).not_to include("<recent_patterns>")
    end
  end
end
