# frozen_string_literal: true

require "json"
require "yaml"
require "pathname"

RSpec.describe "simulation preparedness contract package" do
  let(:repo_root) { Pathname(__dir__).join("../../../../").expand_path }
  let(:contract_path) { repo_root.join("specs/contract/v1/simulation-preparedness.contract.yaml") }
  let(:ledger_schema_path) { repo_root.join("specs/contract/v1/simulation-run-ledger.schema.json") }

  it "defines the gate contract surface and dependencies" do
    payload = YAML.safe_load(contract_path.read, permitted_classes: [], permitted_symbols: [], aliases: false)

    expect(payload["version"]).to eq(1)

    contract = payload.fetch("simulation_preparedness")
    expected_gates = %w[G0 G1 G2 G3 G4 G5]
    expected_statuses = %w[pass fail advisory not_applicable]

    expect(contract.fetch("gate_statuses")).to eq(expected_statuses)
    expect(contract.fetch("gates").keys).to eq(expected_gates)
    expect(contract.dig("activation_policy", "class_1", "required_gates")).to eq(expected_gates)

    class_2_policy = contract.dig("activation_policy", "class_2_plus", "policy")
    expect(class_2_policy).to eq("advisory_until_class_1_stable")

    dependencies = contract.fetch("dependencies")
    dependency_pairs = dependencies.map { |entry| [entry["prerequisite"], entry["enables"]] }
    expect(dependency_pairs).to include(%w[G0 G2], %w[G1 G4])

    contract.fetch("gates").each_value do |gate|
      expect(gate.fetch("evaluator_owner")).to be_a(String)
      expect(gate.fetch("evaluator_owner")).not_to be_empty
      artifacts = gate.fetch("required_artifacts")
      expect(artifacts).to all(be_a(String))
      expect(artifacts).not_to be_empty
    end

    expect(contract.dig("run_ledger", "schema_ref")).to eq("simulation-run-ledger.schema.json")
  end

  it "defines a ledger schema with gate status invariants" do
    schema = JSON.parse(ledger_schema_path.read)

    expected_statuses = %w[pass fail advisory not_applicable]
    expected_gates = %w[G0 G1 G2 G3 G4 G5]

    expect(schema.fetch("required")).to include(
      "schema_version", "run_id", "recorded_at", "commit_sha", "scenario_pack_id", "scenario_class", "seed", "session_id",
      "mode", "gates"
    )

    gate_props = schema.dig("properties", "gates", "properties")
    expect(gate_props.keys).to eq(expected_gates)
    expect(schema.dig("properties", "gates", "required")).to eq(expected_gates)

    status_enum = schema.dig("$defs", "gateResult", "properties", "status", "enum")
    expect(status_enum).to eq(expected_statuses)
    expect(schema.dig("$defs", "gateResult", "required")).to eq(%w[status evaluator_owner required_artifacts])

    mode_enum = schema.dig("properties", "mode", "enum")
    expect(mode_enum).to eq(%w[fixture replay live])
  end
end
