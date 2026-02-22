# frozen_string_literal: true

require "json"

RSpec.describe Agent::SimulationPackContract do
  def deep_dup(payload)
    JSON.parse(JSON.generate(payload))
  end

  let(:base_pack) do
    {
      "version" => 1,
      "id" => "pack-v1",
      "class" => "class_1",
      "execution" => {
        "lane" => "deterministic",
        "isolation" => "run_scoped"
      },
      "scoring_profile" => {
        "id" => "profile-v1",
        "weights" => {
          "correctness" => 0.7,
          "contract_adherence" => 0.15,
          "repair_efficiency" => 0.1,
          "reuse" => 0.05
        }
      },
      "replay" => {
        "mode" => "fixture",
        "seeds" => [11, 19]
      },
      "oracles" => [
        {
          "id" => "oracle-v1",
          "kind" => "calculator_expression",
          "input" => { "expression" => "1 + 1" },
          "expect" => { "result" => 2.0, "tolerance" => 0.0 }
        }
      ]
    }
  end

  it "accepts deterministic execution lane with run-scoped isolation" do
    expect(described_class.validate!(base_pack)).to include("execution" => include("lane" => "deterministic"))
  end

  it "rejects packs missing execution metadata" do
    pack = base_pack.dup
    pack.delete("execution")

    expect do
      described_class.validate!(pack)
    end.to raise_error(ArgumentError, /missing required fields: execution/)
  end

  it "requires scenario for live-shadow packs" do
    pack = deep_dup(base_pack)
    pack["execution"]["lane"] = "live_shadow"

    expect do
      described_class.validate!(pack)
    end.to raise_error(ArgumentError, /scenario must be a Hash/)
  end

  it "accepts live-shadow packs with scripted scenario contract" do
    pack = deep_dup(base_pack)
    pack["execution"]["lane"] = "live_shadow"
    pack["scenario"] = {
      "role" => "calculator",
      "script" => [
        { "call" => "add", "args" => [3] }
      ]
    }

    expect(described_class.validate!(pack)).to include("scenario" => include("role" => "calculator"))
  end
end
