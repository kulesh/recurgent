# frozen_string_literal: true

require "pathname"
require "tmpdir"
require "fileutils"
require "json"
require "yaml"

RSpec.describe Agent::SimulationRunner do
  let(:repo_root) { Pathname(__dir__).join("../../..").expand_path }
  let(:pack_path) { repo_root.join("specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml") }
  let(:edge_pack_path) { repo_root.join("specs/contract/v1/simulation/scenario-packs/calculator-edge-v1.yaml") }
  let(:readiness_contract_path) { repo_root.join("specs/contract/v1/simulation-preparedness.contract.yaml") }
  let(:tmpdir) { Dir.mktmpdir("recurgent-sim-runner-") }
  let(:fixture_root) { File.join(tmpdir, "fixtures") }
  let(:ledger_path) { File.join(tmpdir, "run-ledger.jsonl") }
  let(:trace_log_path) { File.join(tmpdir, "recurgent.jsonl") }
  let(:live_shadow_root) { File.join(tmpdir, "live-shadow") }
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
      live_shadow_root: live_shadow_root,
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
    expect(result.fetch("execution_lane")).to eq("deterministic")
    expect(result.fetch("run_scope_id")).to be_nil
    expect(result.fetch("usage_telemetry")).to eq(
      {
        "provider" => nil,
        "model" => nil,
        "input_tokens" => nil,
        "output_tokens" => nil,
        "total_tokens" => nil,
        "estimated_cost_usd" => nil,
        "availability" => "unknown"
      }
    )
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

  it "executes live-shadow scripts and emits step/trace payloads" do
    mock_provider = instance_double(Agent::Providers::Anthropic)
    allow(Agent::Providers::Anthropic).to receive(:new).and_return(mock_provider)
    allow(mock_provider).to receive(:generate_program).and_return(
      { code: "context[:value] = (context[:value] || 0) + args[0].to_f; result = context[:value]" },
      { code: "context[:value] = (context[:value] || 0) * args[0].to_f; result = context[:value]" }
    )

    live_pack_path = File.join(tmpdir, "calculator-live-shadow.yaml")
    File.write(
      live_pack_path,
      YAML.dump(
        {
          "version" => 1,
          "id" => "calculator-live-shadow-v1",
          "class" => "class_1",
          "execution" => {
            "lane" => "live_shadow",
            "isolation" => "run_scoped"
          },
          "scenario" => {
            "role" => "calculator",
            "model" => Agent::DEFAULT_MODEL,
            "script" => [
              { "step_id" => "add", "call" => "add", "args" => [3] },
              { "step_id" => "multiply", "call" => "multiply", "args" => [4] }
            ]
          },
          "scoring_profile" => {
            "id" => "calculator_live_shadow_v1",
            "weights" => {
              "correctness" => 0.7,
              "contract_adherence" => 0.15,
              "repair_efficiency" => 0.1,
              "reuse" => 0.05
            }
          },
          "replay" => {
            "mode" => "fixture",
            "seeds" => [11]
          },
          "oracles" => [
            {
              "id" => "value-add",
              "kind" => "live_outcome_value",
              "input" => { "step" => "add", "value_path" => "" },
              "expect" => { "value" => 3.0, "tolerance" => 0.0 }
            },
            {
              "id" => "value-multiply",
              "kind" => "live_outcome_value",
              "input" => { "step" => "multiply", "value_path" => "" },
              "expect" => { "value" => 12.0, "tolerance" => 0.0 }
            }
          ]
        }
      )
    )

    result = runner.run_pack(pack_path: live_pack_path, mode: "fixture", session_id: "live-session-a")

    expect(result.fetch("execution_lane")).to eq("live_shadow")
    expect(result.fetch("run_scope_id")).to include("live-shadow:live-session-a:")
    expect(result.dig("usage_telemetry", "availability")).to eq("partial")
    expect(result.dig("usage_telemetry", "provider")).to eq("anthropic")
    expect(result.dig("metrics", "per_seed_results", 0, "step_results").length).to eq(2)
    expect(result.dig("metrics", "per_seed_results", 0, "oracle_results")).to all(include("passed" => true))
  end

  it "compares live-shadow replay using oracle verdicts rather than payload identity" do
    mock_provider = instance_double(Agent::Providers::Anthropic)
    allow(Agent::Providers::Anthropic).to receive(:new).and_return(mock_provider)

    live_pack_path = File.join(tmpdir, "calculator-live-shadow-replay.yaml")
    File.write(
      live_pack_path,
      YAML.dump(
        {
          "version" => 1,
          "id" => "calculator-live-shadow-replay-v1",
          "class" => "class_1",
          "execution" => {
            "lane" => "live_shadow",
            "isolation" => "run_scoped"
          },
          "scenario" => {
            "role" => "calculator",
            "model" => Agent::DEFAULT_MODEL,
            "script" => [
              { "step_id" => "add", "call" => "add", "args" => [3] }
            ]
          },
          "scoring_profile" => {
            "id" => "calculator_live_shadow_replay_v1",
            "weights" => {
              "correctness" => 0.7,
              "contract_adherence" => 0.15,
              "repair_efficiency" => 0.1,
              "reuse" => 0.05
            }
          },
          "replay" => {
            "mode" => "fixture",
            "seeds" => [11]
          },
          "oracles" => [
            {
              "id" => "value-add",
              "kind" => "live_outcome_value",
              "input" => { "step" => "add", "value_path" => "" },
              "expect" => { "value" => 3.0, "tolerance" => 1.0 }
            }
          ]
        }
      )
    )

    allow(mock_provider).to receive(:generate_program).and_return(
      { code: "result = args[0].to_f" },
      { code: "result = args[0].to_f + 0.5" }
    )

    runner.run_pack(pack_path: live_pack_path, mode: "fixture", session_id: "live-session-b")
    replay = runner.run_pack(pack_path: live_pack_path, mode: "replay", session_id: "live-session-b")

    fixture_payload = Agent::SimulationFixtureStore.new(root: fixture_root).read(
      pack_id: "calculator-live-shadow-replay-v1",
      checksum: Agent::SimulationScenarioPack.load(live_pack_path).fetch("checksum_sha256"),
      seed: 11
    )
    replay_payload = replay.dig("metrics", "per_seed_results", 0)

    expect(fixture_payload["step_results"]).not_to eq(replay_payload["step_results"])
    expect(replay_payload["replay_match"]).to eq(true)
  end
end
