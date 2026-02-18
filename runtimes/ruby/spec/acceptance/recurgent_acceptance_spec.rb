# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe "Agent acceptance" do
  let(:provider_class) do
    Class.new do
      def initialize(routes:, errors: {})
        @routes = routes
        @errors = errors
      end

      def generate_program(model:, system_prompt:, user_prompt:, tool_schema:, timeout_seconds: nil)
        _ = [model, system_prompt, tool_schema, timeout_seconds]
        method_name = user_prompt[%r{<method>([^<]+)</method>}, 1]
        raise "Unable to parse method name from user prompt" unless method_name

        error = @errors[method_name]
        raise error if error

        @routes.fetch(method_name) { raise "No deterministic route for method '#{method_name}'" }
      end
    end
  end

  let(:routes) { {} }
  let(:errors) { {} }
  let(:provider) { provider_class.new(routes: routes, errors: errors) }
  let(:runtime_toolstore_root) { Dir.mktmpdir("recurgent-acceptance-toolstore-") }

  def program(code:, dependencies: nil)
    payload = { code: code }
    payload[:dependencies] = dependencies unless dependencies.nil?
    payload
  end

  before do
    allow(Agent::Providers::Anthropic).to receive(:new).and_return(provider)
    allow(Agent).to receive(:default_log_path).and_return(false)
    Agent.reset_runtime_config!
    Agent.configure_runtime(toolstore_root: runtime_toolstore_root)
  end

  after do
    FileUtils.rm_rf(runtime_toolstore_root)
    Agent.reset_runtime_config!
  end

  it "supports a calculator journey with persistent memory" do
    routes.merge!(
      "add" => program(code: "context[:value] = context.fetch(:value, 0) + args[0]; result = context[:value]"),
      "value" => program(code: "result = context.fetch(:value, 0)")
    )

    calculator = Agent.for("calculator")
    calculator.value = 10

    add_outcome = calculator.add(5)
    value_outcome = calculator.value
    expect(add_outcome).to be_ok
    expect(add_outcome.value).to eq(15)
    expect(value_outcome).to be_ok
    expect(value_outcome.value).to eq(15)
  end

  it "supports delegation via child agents" do
    routes.merge!(
      "compute" => program(code: 'helper = Agent.for("calculator"); result = helper.add(2, 3)'),
      "add" => program(code: "result = args[0] + args[1]")
    )

    delegator = Agent.for("delegator")

    compute_outcome = delegator.compute
    expect(compute_outcome).to be_ok
    expect(compute_outcome.value).to eq(5)
  end

  it "records debug logging fields in an end-to-end call" do
    routes.merge!(
      "increment" => program(code: "context[:count] = context.fetch(:count, 0) + 1; result = context[:count]")
    )

    log_dir = Dir.mktmpdir("recurgent-acceptance-")
    log_path = File.join(log_dir, "calls.jsonl")

    calculator = Agent.for("calculator", log: log_path, debug: true)
    increment_outcome = calculator.increment
    expect(increment_outcome).to be_ok
    expect(increment_outcome.value).to eq(1)

    entry = JSON.parse(File.read(log_path))
    expect(entry["role"]).to eq("calculator")
    expect(entry["method"]).to eq("increment")
    expect(entry).to have_key("system_prompt")
    expect(entry).to have_key("user_prompt")
    expect(entry).to have_key("context")
  ensure
    FileUtils.rm_rf(log_dir)
  end

  it "returns provider error outcomes on provider failures" do
    errors["explode_provider"] = StandardError.new("network down")

    agent = Agent.for("agent")

    outcome = agent.explode_provider
    expect(outcome).to be_error
    expect(outcome.error_type).to eq("provider")
    expect(outcome.error_message).to include("network down")
  end

  it "returns execution error outcomes on generated code failure" do
    routes["explode_execution"] = program(code: "raise 'boom'")

    agent = Agent.for("agent")

    outcome = agent.explode_execution
    expect(outcome).to be_error
    expect(outcome.error_type).to eq("execution")
    expect(outcome.error_message).to include("boom")
  end

  it "returns invalid_code outcomes when provider returns nil code" do
    routes["bad_provider_payload"] = nil

    agent = Agent.for("agent")

    outcome = agent.bad_provider_payload
    expect(outcome).to be_error
    expect(outcome.error_type).to eq("invalid_code")
    expect(outcome.error_message).to include("invalid program")
  end

  it "reuses persisted artifacts across agent instances" do
    routes["answer"] = program(code: "result = 42")

    first_agent = Agent.for("calculator")
    outcome1 = first_agent.answer
    expect(outcome1).to be_ok
    expect(outcome1.value).to eq(42)

    # Remove the route and add an error — if artifact reuse works, the provider is never called
    routes.delete("answer")
    errors["answer"] = StandardError.new("provider should not be called for cached artifact")

    second_agent = Agent.for("calculator")
    outcome2 = second_agent.answer
    expect(outcome2).to be_ok
    expect(outcome2.value).to eq(42)
  end

  it "records conversation history across multiple calls" do
    routes.merge!(
      "greet" => program(code: 'result = "hello"'),
      "add" => program(code: "result = args[0] + args[1]"),
      "status" => program(code: 'result = "ok"')
    )

    agent = Agent.for("assistant")
    agent.greet
    agent.add(2, 3)
    agent.status

    history = agent.memory[:conversation_history]
    expect(history.size).to eq(3)

    history.each do |record|
      expect(record).to include(:call_id, :timestamp, :method_name, :outcome_summary)
      expect(record[:speaker]).to eq("user")
      expect(record[:outcome_summary][:status]).to eq("ok")
    end

    expect(history.map { |r| r[:method_name] }).to eq(%w[greet add status])
  end

  it "propagates structured Agent::Outcome.ok values to the caller" do
    routes["analyze"] = program(code: <<~RUBY)
      result = Agent::Outcome.ok(
        summary: "analysis complete",
        items: [1, 2, 3]
      )
    RUBY

    agent = Agent.for("analyst")
    outcome = agent.analyze
    expect(outcome).to be_ok
    expect(outcome.value).to include(summary: "analysis complete", items: [1, 2, 3])
  end

  it "propagates Agent::Outcome.error with typed metadata to the caller" do
    routes["risky"] = program(code: <<~RUBY)
      result = Agent::Outcome.error(
        error_type: "capability_unavailable",
        error_message: "No network access in this runtime",
        retriable: false,
        tool_role: @role,
        method_name: "risky"
      )
    RUBY

    agent = Agent.for("worker")
    outcome = agent.risky
    expect(outcome).to be_error
    expect(outcome.error_type).to eq("capability_unavailable")
    expect(outcome.error_message).to include("No network access")
    expect(outcome.retriable).to eq(false)
  end

  it "persists delegated tool metadata in the tool registry" do
    routes.merge!(
      "plan" => program(code: <<~RUBY),
        helper = delegate(
          "formatter",
          purpose: "format text output",
          deliverable: { type: "string" },
          acceptance: [{ assert: "output is formatted" }],
          failure_policy: { on_error: "return_error" }
        )
        result = "delegation created"
      RUBY
      "format" => program(code: "result = args[0].upcase")
    )

    agent = Agent.for("planner")
    agent.plan

    tools = agent.memory[:tools]
    expect(tools).to have_key("formatter")
    expect(tools["formatter"][:purpose]).to eq("format text output")
  end

  it "passes outcome contract validation when deliverable matches" do
    routes["fetch"] = program(code: 'result = { body: "content", status: 200 }')

    agent = Agent.new(
      "fetcher",
      delegation_contract: {
        purpose: "fetch content",
        deliverable: { type: "object", required: %w[body status] },
        acceptance: [{ assert: "body and status present" }],
        failure_policy: { on_error: "return_error" }
      }
    )

    outcome = agent.fetch
    expect(outcome).to be_ok
    expect(outcome.value).to include("body" => "content", "status" => 200)
  end

  it "returns contract_violation when deliverable shape does not match" do
    routes["fetch"] = program(code: 'result = "just a string"')

    agent = Agent.new(
      "fetcher",
      delegation_contract: {
        purpose: "fetch content",
        deliverable: { type: "object", required: %w[body status] },
        acceptance: [{ assert: "body and status present" }],
        failure_policy: { on_error: "return_error" }
      }
    )

    outcome = agent.fetch
    expect(outcome).to be_error
    expect(outcome.error_type).to eq("contract_violation")
  end

  it "recovers from guardrail violations via retry with feedback" do
    guardrail_mock = instance_double(Agent::Providers::Anthropic)
    allow(Agent::Providers::Anthropic).to receive(:new).and_return(guardrail_mock)

    allow(guardrail_mock).to receive(:generate_program).and_return(
      program(code: 'x = Agent.new("sub"); x.define_singleton_method(:y) { }; result = "bad"'),
      program(code: 'result = "recovered"')
    )

    agent = Agent.for("worker", guardrail_recovery_budget: 2)
    outcome = agent.work
    expect(outcome).to be_ok
    expect(outcome.value).to eq("recovered")
    expect(guardrail_mock).to have_received(:generate_program).twice
  end

  it "extracts and stores capability patterns in pattern memory" do
    routes["fetch_news"] = program(code: <<~RUBY)
      require "net/http"
      require "rss"
      uri = URI("https://example.com/feed.xml")
      xml = Net::HTTP.get(uri)
      feed = RSS::Parser.parse(xml)
      items = feed.items.map { |item| { title: item.title } }
      result = items
    RUBY

    agent = Agent.for("news_reader")
    agent.fetch_news

    events = agent.send(:_pattern_memory_recent_events, role: "news_reader", method_name: "fetch_news", window: 1)
    expect(events.size).to eq(1)
    expect(events.first["capability_patterns"]).to include("http_fetch", "rss_parse")
  end
end
