# frozen_string_literal: true

require "pathname"

RSpec.describe Agent::SimulationScorer do
  let(:repo_root) { Pathname(__dir__).join("../../..").expand_path }
  let(:pack_path) { repo_root.join("specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml") }
  let(:pack) { Agent::SimulationScenarioPack.load(pack_path) }
  let(:scorer) { described_class.new }

  it "produces deterministic golden score vectors" do
    per_seed_results = [
      {
        "seed" => 11,
        "oracle_results" => [
          { "id" => "a", "kind" => "calculator_expression", "passed" => true, "observation" => { "status" => "ok" } },
          { "id" => "b", "kind" => "calculator_expression", "passed" => false,
            "observation" => { "status" => "error" } }
        ]
      },
      {
        "seed" => 19,
        "oracle_results" => [
          { "id" => "c", "kind" => "calculator_expression", "passed" => true, "observation" => { "status" => "ok" } },
          { "id" => "d", "kind" => "calculator_expression", "passed" => true, "observation" => { "status" => "ok" } }
        ]
      }
    ]
    expected = {
      "scorer_version" => "simulation_scorer_v1",
      "components" => {
        "correctness" => 0.75,
        "contract_adherence" => 1.0,
        "repair_efficiency" => 0.75,
        "reuse" => 1.0
      },
      "weights" => {
        "correctness" => 0.7,
        "contract_adherence" => 0.15,
        "repair_efficiency" => 0.1,
        "reuse" => 0.05
      },
      "weighted" => {
        "correctness" => 0.525,
        "contract_adherence" => 0.15,
        "repair_efficiency" => 0.075,
        "reuse" => 0.05
      },
      "overall" => 0.8
    }

    actual = scorer.score(loaded_pack: pack, per_seed_results: per_seed_results)
    expect(actual).to eq(expected)
    expect(scorer.score(loaded_pack: pack, per_seed_results: per_seed_results)).to eq(expected)
  end
end
