#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require_relative "../lib/recurgent"

class DemoProvider
  def initialize
    @calls = Hash.new(0)
  end

  def generate_program(model:, system_prompt:, user_prompt:, tool_schema:, timeout_seconds: nil)
    _ = [model, tool_schema, timeout_seconds]
    role = system_prompt[/called '([^']+)'/, 1]
    method_name = user_prompt[%r{<method>([^<]+)</method>}, 1]
    @calls[[role, method_name]] += 1

    case [role, method_name]
    when %w[observability_demo_tool_builder run]
      { code: tool_builder_run_code }
    when %w[stable_finance_tool analyze]
      { code: 'result = { tool: "stable_finance_tool", topic: args[0], signal: "ok" }' }
    when %w[stable_reasoning_tool analyze]
      { code: 'result = { tool: "stable_reasoning_tool", topic: args[0], signal: "ok" }' }
    when %w[flaky_places_tool analyze]
      { code: nil }
    else
      { code: "result = nil" }
    end
  end

  private

  def tool_builder_run_code
    <<~RUBY
      tools = [
        delegate(
          "stable_finance_tool",
          purpose: "Assess business signal quality for the topic",
          deliverable: {type: "object", required: ["tool", "topic", "signal"]},
          acceptance: [{assert: "signal is present"}],
          failure_policy: {on_error: "continue_with_partials"}
        ),
        delegate(
          "flaky_places_tool",
          purpose: "Validate location-sensitive claims for the topic",
          deliverable: {type: "object", required: ["tool", "topic", "signal"]},
          acceptance: [{assert: "signal is present"}],
          failure_policy: {on_error: "continue_with_partials", retry_hint: "switch tool if repeated failures"}
        ),
        delegate(
          "stable_reasoning_tool",
          purpose: "Synthesize final reasoning signal for the topic",
          deliverable: {type: "object", required: ["tool", "topic", "signal"]},
          acceptance: [{assert: "signal is present"}],
          failure_policy: {on_error: "continue_with_partials"}
        )
      ]

      initial_topics = ["margin analysis", "restaurant validation", "final synthesis"]
      initial_outcomes = tools.zip(initial_topics).map do |tool, topic|
        tool.analyze(topic)
      end

      follow_up_outcomes = 2.times.map do
        tools[1].analyze("restaurant validation retry")
      end

      all_outcomes = initial_outcomes + follow_up_outcomes
      context[:all_outcomes] = all_outcomes.map(&:to_h)

      successful = all_outcomes.select(&:ok?).map(&:value)
      failures = all_outcomes.select(&:error?).map do |outcome|
        {
          role: outcome.tool_role,
          type: outcome.error_type,
          retriable: outcome.retriable,
          message: outcome.error_message
        }
      end

      result = {
        ok_count: successful.length,
        error_count: failures.length,
        failures: failures,
        synthesis: "continued_despite_partial_failure"
      }
    RUBY
  end
end

demo_provider = DemoProvider.new
singleton = class << Agent::Providers::Anthropic; self; end
singleton.send(:define_method, :new) { demo_provider }

log_path = File.join(Dir.home, ".local", "state", "recurgent", "observability_demo.jsonl")
FileUtils.mkdir_p(File.dirname(log_path))
FileUtils.rm_f(log_path)

tool_builder = Agent.for(
  "observability_demo_tool_builder",
  log: log_path,
  debug: true,
  max_generation_attempts: 2
)

outcome = tool_builder.run
puts "Outcome status: #{outcome.status}"
puts "Outcome value: #{outcome.value.inspect}"
puts "Log path: #{log_path}"
