# frozen_string_literal: true

require "json"
require "pathname"
require "tmpdir"
require "fileutils"

RSpec.describe Agent::SimulationTraceSchemaValidator do
  let(:tmpdir) { Dir.mktmpdir("recurgent-trace-schema-") }
  let(:log_path) { File.join(tmpdir, "recurgent.jsonl") }
  let(:validator) { described_class.new }

  after do
    FileUtils.remove_entry(tmpdir) if tmpdir && File.exist?(tmpdir)
  end

  it "passes for valid log entries with required fields" do
    payload = {
      "timestamp" => "2026-02-22T00:00:00.000Z",
      "role" => "calculator",
      "model" => "claude-sonnet-4-5-20250929",
      "method" => "add",
      "args" => [1],
      "kwargs" => {},
      "code" => "result = 2",
      "duration_ms" => 1.2,
      "generation_attempt" => 1,
      "outcome_status" => "ok"
    }
    File.write(log_path, "#{JSON.generate(payload)}\n")

    result = validator.validate(log_path: log_path)
    expect(result).to eq({ "valid" => true, "entry_count" => 1 })
  end

  it "returns first invalid location diagnostics when schema shape is broken" do
    payload = {
      "timestamp" => "2026-02-22T00:00:00.000Z",
      "role" => "calculator",
      "model" => "claude-sonnet-4-5-20250929",
      "method" => "add",
      "args" => [1],
      "kwargs" => {},
      "code" => "result = 2",
      "duration_ms" => "not_numeric",
      "generation_attempt" => 1
    }
    File.write(log_path, "#{JSON.generate(payload)}\n")

    result = validator.validate(log_path: log_path)
    expect(result.fetch("valid")).to eq(false)
    expect(result.fetch("first_invalid_field_path")).to eq("$.duration_ms")
    expect(result.fetch("first_invalid_reason")).to include("expected Numeric")
  end
end
