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
        method_name = user_prompt[/Someone called '([^']+)'/, 1]
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

  def program(code:, dependencies: nil)
    payload = { code: code }
    payload[:dependencies] = dependencies unless dependencies.nil?
    payload
  end

  before do
    allow(Agent::Providers::Anthropic).to receive(:new).and_return(provider)
    allow(Agent).to receive(:default_log_path).and_return(false)
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

    counter = Agent.for("counter", log: log_path, debug: true)
    increment_outcome = counter.increment
    expect(increment_outcome).to be_ok
    expect(increment_outcome.value).to eq(1)

    entry = JSON.parse(File.read(log_path))
    expect(entry["role"]).to eq("counter")
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
end
