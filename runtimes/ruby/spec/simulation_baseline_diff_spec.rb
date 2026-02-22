# frozen_string_literal: true

RSpec.describe Agent::SimulationBaselineDiff do
  let(:diff_engine) { described_class.new }

  it "returns no_baseline when baseline snapshot is missing" do
    current = { "run_id" => "run-current", "overall_score" => 1.0, "gate_statuses" => { "G0" => "pass" } }
    result = diff_engine.diff(current_snapshot: current, baseline_snapshot: nil)
    expect(result.fetch("classification")).to eq("no_baseline")
    expect(result.fetch("suspected_causes")).to include("baseline_missing")
  end

  it "classifies score drops as regressed and captures gate changes" do
    baseline = {
      "run_id" => "run-base",
      "overall_score" => 1.0,
      "gate_statuses" => { "G0" => "pass", "G1" => "pass", "G2" => "pass" }
    }
    current = {
      "run_id" => "run-current",
      "overall_score" => 0.8,
      "gate_statuses" => { "G0" => "pass", "G1" => "advisory", "G2" => "pass" }
    }

    result = diff_engine.diff(current_snapshot: current, baseline_snapshot: baseline)
    expect(result.fetch("classification")).to eq("regressed")
    expect(result.fetch("score_delta")).to eq(-0.2)
    expect(result.fetch("suspected_causes").join(" ")).to include("score_vector_shift", "gate_regression")
  end
end
