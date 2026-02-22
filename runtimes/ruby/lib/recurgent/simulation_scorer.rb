# frozen_string_literal: true

class Agent
  # Agent::SimulationScorer computes deterministic score vectors for simulation packs.
  class SimulationScorer
    VERSION = "simulation_scorer_v1"

    def score(loaded_pack:, per_seed_results:)
      weights = _weights_from_pack(loaded_pack)
      components = _component_scores(per_seed_results)
      weighted = weights.transform_keys(&:to_s).each_with_object({}) do |(key, weight), memo|
        memo[key] = _round(components.fetch(key) * weight)
      end
      {
        "scorer_version" => VERSION,
        "components" => components,
        "weights" => weights.transform_keys(&:to_s).transform_values { |value| _round(value) },
        "weighted" => weighted,
        "overall" => _round(weighted.values.sum)
      }
    end

    private

    def _weights_from_pack(loaded_pack)
      profile = loaded_pack.fetch("scoring_profile")
      weights = (profile["weights"] || profile[:weights]).transform_keys(&:to_s).transform_values(&:to_f)
      Agent::SimulationPackContract::REQUIRED_WEIGHT_KEYS.each_with_object({}) do |key, normalized|
        normalized[key] = weights.fetch(key, 0.0)
      end
    end

    def _component_scores(per_seed_results)
      oracle_results = _oracle_results(per_seed_results)
      total = oracle_results.length.to_f
      return _zero_components if total.zero?

      {
        "correctness" => _round(_pass_ratio(oracle_results, total: total)),
        "contract_adherence" => _round(_contract_ratio(oracle_results, total: total)),
        "repair_efficiency" => _round(_repair_efficiency_ratio(oracle_results, total: total)),
        "reuse" => 1.0
      }
    end

    def _oracle_results(per_seed_results)
      per_seed_results.flat_map { |result| result.fetch("oracle_results") }
    end

    def _pass_ratio(oracle_results, total:)
      oracle_results.count { |result| result["passed"] }.to_f / total
    end

    def _contract_ratio(oracle_results, total:)
      contract_ok = oracle_results.count do |result|
        result.key?("id") && result.key?("kind") && result.key?("observation")
      end
      contract_ok.to_f / total
    end

    def _repair_efficiency_ratio(oracle_results, total:)
      repairs_needed = oracle_results.count do |result|
        observation = result.fetch("observation")
        observation.is_a?(Hash) && observation["status"] == "error" && !result["passed"]
      end
      1.0 - (repairs_needed.to_f / total)
    end

    def _zero_components
      {
        "correctness" => 0.0,
        "contract_adherence" => 0.0,
        "repair_efficiency" => 0.0,
        "reuse" => 0.0
      }
    end

    def _round(value)
      value.to_f.round(6)
    end
  end
end
