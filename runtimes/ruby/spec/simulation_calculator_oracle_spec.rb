# frozen_string_literal: true

RSpec.describe Agent::SimulationCalculatorOracle do
  subject(:oracle) { described_class.new }

  it "evaluates assistant follow-up continuity oracle" do
    observation = oracle.evaluate(
      {
        "id" => "followup",
        "kind" => "assistant_followup_case",
        "input" => {
          "conversation_history" => [{ "outcome_summary" => { "content_ref" => "content:abc" } }],
          "follow_up" => {
            "query" => "format that in markdown",
            "resolved_content_ref" => "content:abc"
          }
        },
        "expect" => {
          "requires_content_ref" => true
        }
      }
    )

    expect(observation.fetch("passed")).to eq(true)
    expect(observation.fetch("status")).to eq("ok")
  end

  it "evaluates provenance envelope oracle" do
    observation = oracle.evaluate(
      {
        "id" => "provenance",
        "kind" => "provenance_envelope_case",
        "input" => {
          "success_payload" => {
            "provenance" => {
              "sources" => [
                {
                  "uri" => "https://example.com/data",
                  "fetched_at" => "2026-02-22T00:00:00Z",
                  "retrieval_tool" => "fetcher",
                  "retrieval_mode" => "live"
                }
              ]
            }
          }
        },
        "expect" => {
          "min_sources" => 1,
          "required_source_keys" => %w[uri fetched_at retrieval_tool retrieval_mode],
          "allowed_retrieval_modes" => %w[live cached fixture knowledge_base]
        }
      }
    )

    expect(observation.fetch("passed")).to eq(true)
    expect(observation.fetch("status")).to eq("ok")
  end

  it "evaluates debate orchestration oracle" do
    observation = oracle.evaluate(
      {
        "id" => "debate",
        "kind" => "debate_orchestration_case",
        "input" => {
          "contributions" => [
            { "panelist" => "engineer", "round" => 1 },
            { "panelist" => "critic", "round" => 1 },
            { "panelist" => "philosopher", "round" => 1 },
            { "panelist" => "engineer", "round" => 2 },
            { "panelist" => "critic", "round" => 2 },
            { "panelist" => "philosopher", "round" => 2 }
          ],
          "moderation" => {
            "final_synthesis_present" => true
          }
        },
        "expect" => {
          "min_panelists" => 3,
          "min_rounds" => 2,
          "require_final_synthesis" => true
        }
      }
    )

    expect(observation.fetch("passed")).to eq(true)
    expect(observation.fetch("status")).to eq("ok")
  end

  it "evaluates typed boundary error oracle" do
    observation = oracle.evaluate(
      {
        "id" => "typed-error",
        "kind" => "typed_error_boundary_case",
        "input" => {
          "outcome" => {
            "status" => "error",
            "error_type" => "capability_unavailable",
            "retriable" => false
          }
        },
        "expect" => {
          "allowed_error_types" => ["capability_unavailable"],
          "require_non_retriable" => true
        }
      }
    )

    expect(observation.fetch("passed")).to eq(true)
    expect(observation.fetch("status")).to eq("ok")
  end
end
