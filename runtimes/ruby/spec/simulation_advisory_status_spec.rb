# frozen_string_literal: true

require "json"
require "tmpdir"
require "fileutils"

RSpec.describe Agent::SimulationAdvisoryStatus do
  let(:tmpdir) { Dir.mktmpdir("recurgent-sim-advisory-") }
  let(:ledger_path) { File.join(tmpdir, "run-ledger.jsonl") }

  after do
    FileUtils.remove_entry(tmpdir) if tmpdir && File.exist?(tmpdir)
  end

  it "summarizes advisory class-2 replay entries by pack" do
    entries = [
      _entry(pack_id: "assistant-continuity-v1", recorded_at: "2026-02-22T01:00:00Z", score: 0.7,
             gate_statuses: { "G2" => "advisory", "G3" => "pass" }),
      _entry(pack_id: "assistant-continuity-v1", recorded_at: "2026-02-22T02:00:00Z", score: 0.8,
             gate_statuses: { "G2" => "pass", "G3" => "pass" }),
      _entry(pack_id: "debate-orchestration-v1", recorded_at: "2026-02-22T03:00:00Z", score: 0.6,
             gate_statuses: { "G2" => "advisory", "G3" => "pass" })
    ]

    File.open(ledger_path, "w") do |file|
      entries.each { |entry| file.puts(JSON.generate(entry)) }
    end

    analysis = described_class.new(ledger_path: ledger_path).analyze
    expect(analysis.fetch("pack_count")).to eq(2)
    expect(analysis.fetch("total_replay_runs")).to eq(3)

    assistant = analysis.fetch("pack_summaries").find { |item| item.fetch("pack_id") == "assistant-continuity-v1" }
    expect(assistant.fetch("run_count")).to eq(2)
    expect(assistant.dig("score_trend", "delta")).to eq(0.1)

    global_signatures = analysis.fetch("global_failure_signatures")
    expect(global_signatures).to include(hash_including("signature" => "gate:G2=advisory"))
  end

  def _entry(pack_id:, recorded_at:, score:, gate_statuses:)
    {
      "schema_version" => 1,
      "run_id" => "#{pack_id}-#{recorded_at}",
      "recorded_at" => recorded_at,
      "scenario_pack_id" => pack_id,
      "scenario_class" => "class_2_plus",
      "mode" => "replay",
      "score_vector" => { "overall" => score },
      "metrics" => {
        "seeds" => [11, 19, 23],
        "baseline_diff_report" => { "classification" => "improved" }
      },
      "gates" => gate_statuses.transform_values { |status| { "status" => status } }
    }
  end
end
