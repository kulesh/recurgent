# frozen_string_literal: true

require "json"
require "tmpdir"
require "fileutils"
require "time"

RSpec.describe Agent::SimulationStabilizationWindow do
  let(:tmpdir) { Dir.mktmpdir("recurgent-sim-window-") }
  let(:ledger_path) { File.join(tmpdir, "run-ledger.jsonl") }

  after do
    FileUtils.remove_entry(tmpdir) if tmpdir && File.exist?(tmpdir)
  end

  it "reports window_met when trailing qualifying sessions satisfy all thresholds" do
    FileUtils.mkdir_p(File.dirname(ledger_path))
    File.open(ledger_path, "w") do |file|
      20.times do |idx|
        session_id = "session-#{idx + 1}"
        timestamp = Time.utc(2026, 2, 20 + (idx % 3), 1, 0, idx).iso8601
        file.puts(JSON.generate(_entry(session_id: session_id, pack_id: "calculator-core-v1", recorded_at: timestamp)))
        file.puts(JSON.generate(_entry(session_id: session_id, pack_id: "calculator-edge-v1", recorded_at: timestamp)))
      end
    end

    analysis = described_class.new(ledger_path: ledger_path).analyze
    expect(analysis.fetch("window_met")).to eq(true)
    expect(analysis.dig("observed", "trailing_consecutive_qualifying")).to eq(20)
    expect(analysis.dig("observed", "distinct_seed_count")).to eq(5)
    expect(analysis.dig("observed", "distinct_day_count")).to eq(3)
  end

  it "resets trailing consecutive count when a session fails required gates" do
    FileUtils.mkdir_p(File.dirname(ledger_path))
    File.open(ledger_path, "w") do |file|
      5.times do |idx|
        session_id = "session-pass-#{idx + 1}"
        timestamp = Time.utc(2026, 2, 20, 2, 0, idx).iso8601
        file.puts(JSON.generate(_entry(session_id: session_id, pack_id: "calculator-core-v1", recorded_at: timestamp)))
        file.puts(JSON.generate(_entry(session_id: session_id, pack_id: "calculator-edge-v1", recorded_at: timestamp)))
      end

      failed_timestamp = Time.utc(2026, 2, 21, 2, 0, 0).iso8601
      file.puts(JSON.generate(_entry(session_id: "session-fail", pack_id: "calculator-core-v1", recorded_at: failed_timestamp,
                                     gate_overrides: { "G2" => "fail" })))
      file.puts(JSON.generate(_entry(session_id: "session-fail", pack_id: "calculator-edge-v1", recorded_at: failed_timestamp)))

      3.times do |idx|
        session_id = "session-tail-#{idx + 1}"
        timestamp = Time.utc(2026, 2, 22, 2, 0, idx).iso8601
        file.puts(JSON.generate(_entry(session_id: session_id, pack_id: "calculator-core-v1", recorded_at: timestamp)))
        file.puts(JSON.generate(_entry(session_id: session_id, pack_id: "calculator-edge-v1", recorded_at: timestamp)))
      end
    end

    analysis = described_class.new(ledger_path: ledger_path).analyze
    expect(analysis.fetch("window_met")).to eq(false)
    expect(analysis.dig("observed", "trailing_consecutive_qualifying")).to eq(3)
    expect(analysis.fetch("reset_events").length).to eq(1)
    expect(analysis.fetch("reset_events").first.fetch("reasons").first).to include("gate_failures")
  end

  it "marks session as non-qualifying when a required pack replay entry is missing" do
    FileUtils.mkdir_p(File.dirname(ledger_path))
    timestamp = Time.utc(2026, 2, 22, 3, 0, 0).iso8601
    File.write(ledger_path, "#{JSON.generate(_entry(session_id: "session-missing-edge", pack_id: "calculator-core-v1", recorded_at: timestamp))}\n")

    analysis = described_class.new(ledger_path: ledger_path).analyze
    expect(analysis.fetch("window_met")).to eq(false)
    expect(analysis.fetch("session_records").first.fetch("qualifying")).to eq(false)
    expect(analysis.fetch("session_records").first.fetch("reasons").first).to include("missing_required_packs")
  end

  def _entry(session_id:, pack_id:, recorded_at:, gate_overrides: {})
    statuses = %w[G0 G1 G2 G3 G4 G5].to_h do |gate|
      [gate, { "status" => gate_overrides.fetch(gate, "pass") }]
    end
    {
      "schema_version" => 1,
      "run_id" => "#{session_id}-#{pack_id}",
      "recorded_at" => recorded_at,
      "commit_sha" => "deadbeef",
      "scenario_pack_id" => pack_id,
      "scenario_class" => "class_1",
      "seed" => 11,
      "session_id" => session_id,
      "mode" => "replay",
      "score_vector" => { "overall" => 1.0 },
      "scorer_version" => "simulation_scorer_v1",
      "metrics" => { "seeds" => [11, 19, 23, 31, 43] },
      "gates" => statuses
    }
  end
end
