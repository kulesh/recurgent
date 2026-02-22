# frozen_string_literal: true

require "pathname"
require "tmpdir"
require "fileutils"
require "json"

RSpec.describe Agent::SimulationRunner do
  let(:repo_root) { Pathname(__dir__).join("../../..").expand_path }
  let(:pack_path) { repo_root.join("specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml") }
  let(:edge_pack_path) { repo_root.join("specs/contract/v1/simulation/scenario-packs/calculator-edge-v1.yaml") }
  let(:readiness_contract_path) { repo_root.join("specs/contract/v1/simulation-preparedness.contract.yaml") }
  let(:tmpdir) { Dir.mktmpdir("recurgent-sim-runner-") }
  let(:fixture_root) { File.join(tmpdir, "fixtures") }
  let(:ledger_path) { File.join(tmpdir, "run-ledger.jsonl") }
  let(:trace_log_path) { File.join(tmpdir, "recurgent.jsonl") }
  let(:valid_trace_entry) do
    {
      "timestamp" => "2026-02-22T00:00:00.000Z",
      "role" => "calculator",
      "model" => "claude-sonnet-4-5-20250929",
      "method" => "add",
      "args" => [1],
      "kwargs" => {},
      "code" => "result = 2",
      "duration_ms" => 1.5,
      "generation_attempt" => 1
    }
  end
  let(:runner) do
    Agent::SimulationRunner.new(
      readiness_contract_path: readiness_contract_path,
      fixture_root: fixture_root,
      ledger_path: ledger_path,
      operational_mode: "local",
      now: -> { Time.utc(2026, 2, 22, 1, 0, 0) },
      commit_sha: "deadbeef"
    )
  end

  after do
    FileUtils.remove_entry(tmpdir) if tmpdir && File.exist?(tmpdir)
  end

  it "writes fixture artifacts and run ledger entries in fixture mode" do
    result = runner.run_pack(pack_path: pack_path, mode: "fixture", session_id: "session-a", seeds: [19, 11])

    expect(result.fetch("mode")).to eq("fixture")
    expect(result.fetch("seed")).to eq(11)
    expect(result.dig("metrics", "seeds")).to eq([11, 19])
    expect(result.dig("gates", "G0", "status")).to eq("pass")
    expect(result.dig("gates", "G1", "status")).to eq("advisory")
    expect(result.dig("gates", "G2", "status")).to eq("advisory")
    expect(result.dig("gates", "G3", "status")).to eq("advisory")
    expect(result.dig("gates", "G4", "status")).to eq("pass")
    expect(result.fetch("scorer_version")).to eq("simulation_scorer_v1")
    expect(result.fetch("score_vector")).to include("overall")
    expect(result.dig("metrics", "baseline_diff_report", "classification")).to eq("no_baseline")

    fixture_paths = Dir[File.join(fixture_root, "**", "*.json")]
    expect(fixture_paths.length).to eq(2)

    ledger_entries = Agent::SimulationRunLedger.new(path: ledger_path).entries
    expect(ledger_entries.length).to eq(1)
    expect(ledger_entries.first.fetch("run_id")).to eq(result.fetch("run_id"))
  end

  it "replays fixture artifacts deterministically in replay mode" do
    runner.run_pack(pack_path: pack_path, mode: "fixture", session_id: "session-a")
    replay = runner.run_pack(pack_path: pack_path, mode: "replay", session_id: "session-a")
    replay_second = runner.run_pack(pack_path: pack_path, mode: "replay", session_id: "session-a")

    expect(replay.fetch("mode")).to eq("replay")
    expect(replay.dig("metrics", "replay_stability")).to eq(1.0)
    expect(replay.dig("gates", "G1", "status")).to eq("pass")
    expect(replay.dig("gates", "G2", "status")).to eq("advisory")
    expect(replay.dig("gates", "G4", "status")).to eq("pass")
    expect(replay_second.dig("gates", "G2", "status")).to eq("pass")
    expect(replay_second.dig("metrics", "baseline_diff_report", "classification")).to eq("improved")
    expect(replay.dig("metrics", "per_seed_results")).to all(include("replay_match" => true))
  end

  it "produces identical per-seed result vectors for same pack/seeds" do
    run_a = runner.run_pack(pack_path: pack_path, mode: "fixture", seeds: [11, 19, 23], session_id: "session-a")
    run_b = runner.run_pack(pack_path: pack_path, mode: "fixture", seeds: [23, 19, 11], session_id: "session-b")

    expect(run_a.dig("metrics", "per_seed_results")).to eq(run_b.dig("metrics", "per_seed_results"))
  end

  it "applies G3 trace-schema gate when trace log is provided" do
    File.write(trace_log_path, "#{JSON.generate(valid_trace_entry)}\n")

    pass_result = runner.run_pack(pack_path: pack_path, mode: "fixture", trace_log_path: trace_log_path)
    expect(pass_result.dig("gates", "G3", "status")).to eq("pass")

    invalid_entry = valid_trace_entry.merge("duration_ms" => "bad")
    File.write(trace_log_path, "#{JSON.generate(invalid_entry)}\n")

    fail_result = runner.run_pack(pack_path: pack_path, mode: "fixture", trace_log_path: trace_log_path)
    expect(fail_result.dig("gates", "G3", "status")).to eq("fail")
    expect(fail_result.dig("gates", "G3", "message")).to include("$.duration_ms")
  end

  it "supports calculator edge error pack without raising runtime exceptions" do
    result = runner.run_pack(pack_path: edge_pack_path, mode: "fixture")
    per_seed_results = result.dig("metrics", "per_seed_results")
    expect(per_seed_results).not_to be_empty

    all_oracles_pass = per_seed_results.flat_map { |seed| seed.fetch("oracle_results") }.all? { |oracle| oracle.fetch("passed") }
    expect(all_oracles_pass).to eq(true)
  end

  it "marks G5 as pass in ci operational mode" do
    ci_runner = Agent::SimulationRunner.new(
      readiness_contract_path: readiness_contract_path,
      fixture_root: fixture_root,
      ledger_path: ledger_path,
      operational_mode: "ci",
      now: -> { Time.utc(2026, 2, 22, 1, 0, 0) },
      commit_sha: "deadbeef"
    )

    result = ci_runner.run_pack(pack_path: pack_path, mode: "fixture")
    expect(result.dig("gates", "G5", "status")).to eq("pass")
    expect(result.dig("gates", "G5", "message")).to include("ci readiness gate executed")
  end

  it "marks G5 as fail in nightly mode when trend report path is missing" do
    nightly_runner = Agent::SimulationRunner.new(
      readiness_contract_path: readiness_contract_path,
      fixture_root: fixture_root,
      ledger_path: ledger_path,
      operational_mode: "nightly",
      nightly_trend_report_path: "",
      now: -> { Time.utc(2026, 2, 22, 1, 0, 0) },
      commit_sha: "deadbeef"
    )

    result = nightly_runner.run_pack(pack_path: pack_path, mode: "fixture")
    expect(result.dig("gates", "G5", "status")).to eq("fail")
    expect(result.dig("gates", "G5", "message")).to include("nightly trend report path missing")
  end
end
