# frozen_string_literal: true

require "pathname"

RSpec.describe Agent::SimulationScenarioPack do
  let(:repo_root) { Pathname(__dir__).join("../../../../").expand_path }
  let(:packs_root) { repo_root.join("specs/contract/v1/simulation/scenario-packs") }
  let(:pack_paths) { Dir[File.join(packs_root, "*.yaml")] }

  it "ships at least two class-1 calculator packs" do
    expect(pack_paths.length).to be >= 2
    ids = pack_paths.map do |path|
      payload = Agent::SimulationScenarioPack.load(path)
      expect(payload.fetch("class")).to eq("class_1")
      payload.fetch("id")
    end

    expect(ids).to include("calculator-core-v1", "calculator-edge-v1")
  end

  it "validates scoring profile and replay contract for each pack" do
    pack_paths.each do |path|
      payload = Agent::SimulationScenarioPack.load(path)
      replay = payload.fetch("replay")
      scoring = payload.fetch("scoring_profile")

      expect(%w[fixture replay live]).to include(replay.fetch("mode"))
      expect(replay.fetch("seeds")).to all(be_a(Integer))
      expect(replay.fetch("seeds").uniq).to eq(replay.fetch("seeds"))

      weights = scoring.fetch("weights")
      expect(weights.keys).to contain_exactly("correctness", "contract_adherence", "repair_efficiency", "reuse")
      expect(weights.values.sum.round(6)).to eq(1.0)
    end
  end

  it "adds a deterministic checksum to loaded payloads" do
    payload = Agent::SimulationScenarioPack.load(pack_paths.first)
    expect(payload.fetch("checksum_sha256")).to match(/\A[0-9a-f]{64}\z/)
  end
end
