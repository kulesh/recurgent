#!/usr/bin/env ruby
# frozen_string_literal: true

# Throwaway parity harness for evaluating RubyLLM as a drop-in replacement
# for the native Anthropic/OpenAI providers (issue #64). This harness is NOT
# production test code — it runs real LLM calls, produces a side-by-side
# report, and is deleted once the go/no-go decision is made.
#
# Usage:
#   RECURGENT_PROVIDER_MODE=native   bundle exec ruby runtimes/ruby/parity/run.rb
#   RECURGENT_PROVIDER_MODE=rubyllm  bundle exec ruby runtimes/ruby/parity/run.rb
#   PARITY_N=5 ... (default: 3 iterations per scenario/model)
#
# Output:
#   runtimes/ruby/parity/results-<mode>.json   — machine-readable per-run signal
#   runtimes/ruby/parity/report-<mode>.md      — human-readable summary
#
# Requires ANTHROPIC_API_KEY and/or OPENAI_API_KEY in the environment; skips
# any tier whose key is missing.

require_relative "../lib/recurgent"
require "json"
require "time"
require "fileutils"

$stdout.sync = true

ANTHROPIC_MODEL = "claude-sonnet-4-5-20250929"
OPENAI_MODEL = "gpt-4o-mini"

N_ITERATIONS = Integer(ENV.fetch("PARITY_N", "3"))
PROVIDER_MODE = ENV.fetch("RECURGENT_PROVIDER_MODE", "native")

abort "RECURGENT_PROVIDER_MODE must be 'native' or 'rubyllm' (got: #{PROVIDER_MODE.inspect})" unless %w[native rubyllm].include?(PROVIDER_MODE)

def available_models
  models = []
  models << ANTHROPIC_MODEL if ENV["ANTHROPIC_API_KEY"]
  models << OPENAI_MODEL if ENV["OPENAI_API_KEY"]
  models
end

# The mode switch only has an effect once the RubyLLM adapter lands. Until
# then both modes exercise the native path — which lets us validate the
# harness itself against the status quo (step 2 of the plan).
def agent_options(model)
  opts = { model: model }
  opts[:provider] = :rubyllm if PROVIDER_MODE == "rubyllm"
  opts
end

# --- Scenarios ---------------------------------------------------------------
#
# Each scenario returns { ok:, assertions:, error: }. `ok` is the AND of all
# assertions. Assertions are coarse (e.g. "value rounds to 8", "response
# mentions Alice") so LLM nondeterminism doesn't produce false negatives.

def run_calculator(model:) # rubocop:disable Metrics/AbcSize
  assertions = {}
  calc = Agent.for("calculator", **agent_options(model))

  calc.memory = 5
  add_outcome = calc.add(3)
  multiply_outcome = calc.multiply(4)

  assertions[:add_ok] = add_outcome.ok?
  assertions[:add_yields_eight] = add_outcome.ok? && add_outcome.value.to_f.round == 8
  assertions[:multiply_ok] = multiply_outcome.ok?
  assertions[:multiply_yields_thirty_two] = multiply_outcome.ok? && multiply_outcome.value.to_f.round == 32

  { ok: assertions.values.all?, assertions: assertions, error: nil }
rescue StandardError => e
  { ok: false, assertions: assertions, error: "#{e.class}: #{e.message}" }
end

def run_debate(model:)
  assertions = {}
  debate = Agent.for("debate_show_host", **agent_options(model))

  result = debate.moderate(
    topic: "Should programming languages have garbage collection?",
    panelists: [
      "systems programmer who values performance",
      "web developer who values productivity",
      "philosopher questioning ownership"
    ],
    rounds: 2
  )

  assertions[:moderate_ok] = result.ok?
  assertions[:result_non_trivial] = result.ok? && result.value.to_s.length > 100

  { ok: assertions.values.all?, assertions: assertions, error: nil }
rescue StandardError => e
  { ok: false, assertions: assertions, error: "#{e.class}: #{e.message}" }
end

def run_assistant(model:)
  assertions = {}
  assistant = Agent.for("personal assistant that remembers conversation history", **agent_options(model))

  first = assistant.ask("My name is Alice and my favorite color is purple.")
  second = assistant.ask("What is my name and favorite color?")

  assertions[:first_ok] = first.ok?
  assertions[:second_ok] = second.ok?
  recall_text = second.ok? ? second.value.to_s.downcase : ""
  assertions[:remembers_name] = recall_text.include?("alice")
  assertions[:remembers_color] = recall_text.include?("purple")

  { ok: assertions.values.all?, assertions: assertions, error: nil }
rescue StandardError => e
  { ok: false, assertions: assertions, error: "#{e.class}: #{e.message}" }
end

SCENARIOS = {
  "calculator" => method(:run_calculator),
  "debate" => method(:run_debate),
  "assistant" => method(:run_assistant)
}.freeze

# --- Orchestration -----------------------------------------------------------

models = available_models
abort "No API keys found. Set ANTHROPIC_API_KEY and/or OPENAI_API_KEY." if models.empty?

puts "=== Parity harness ==="
puts "Provider mode: #{PROVIDER_MODE}"
puts "Iterations per (scenario, model): #{N_ITERATIONS}"
puts "Models: #{models.join(", ")}"
puts

started_overall = Time.now
results = []

models.each do |model|
  SCENARIOS.each do |name, fn|
    print "#{name.ljust(11)} / #{model}  "
    N_ITERATIONS.times do |i|
      started_at = Time.now
      outcome = fn.call(model: model)
      latency_ms = ((Time.now - started_at) * 1000).to_i
      results << {
        scenario: name,
        model: model,
        provider_mode: PROVIDER_MODE,
        iteration: i,
        ok: outcome[:ok],
        assertions: outcome[:assertions],
        error: outcome[:error],
        latency_ms: latency_ms
      }
      print(outcome[:ok] ? "." : "x")
    end
    puts
  end
end

total_seconds = (Time.now - started_overall).to_i

# --- Output ------------------------------------------------------------------

FileUtils.mkdir_p(__dir__)
results_path = File.join(__dir__, "results-#{PROVIDER_MODE}.json")
report_path = File.join(__dir__, "report-#{PROVIDER_MODE}.md")

File.write(results_path, JSON.pretty_generate(results))

lines = []
lines << "# Parity report — `#{PROVIDER_MODE}`"
lines << ""
lines << "_Generated: #{Time.now.utc.iso8601}_  "
lines << "_Total duration: #{total_seconds}s_  "
lines << "_Iterations per (scenario, model): **#{N_ITERATIONS}**_"
lines << ""
lines << "## Summary"
lines << ""
lines << "| Scenario | Model | Pass rate | Mean latency (ms) |"
lines << "|----------|-------|-----------|-------------------|"
models.each do |model|
  SCENARIOS.each_key do |name|
    rows = results.select { |r| r[:scenario] == name && r[:model] == model }
    next if rows.empty?

    passes = rows.count { |r| r[:ok] }
    pass_pct = (passes * 100 / rows.size)
    mean_ms = rows.sum { |r| r[:latency_ms] } / rows.size
    lines << "| #{name} | `#{model}` | #{pass_pct}% (#{passes}/#{rows.size}) | #{mean_ms} |"
  end
end

lines << ""
lines << "## Failures"
lines << ""
failures = results.reject { |r| r[:ok] }
if failures.empty?
  lines << "_No failures._"
else
  failures.each do |f|
    header = "- **#{f[:scenario]}** / `#{f[:model]}` / iter #{f[:iteration]} (#{f[:latency_ms]} ms)"
    lines << header
    if f[:error]
      lines << "  - Error: `#{f[:error]}`"
    else
      failed_keys = f[:assertions].reject { |_, v| v }.keys
      lines << "  - Failed assertions: #{failed_keys.join(", ")}"
    end
  end
end

File.write(report_path, "#{lines.join("\n")}\n")

puts
puts "Results: #{results_path}"
puts "Report:  #{report_path}"
