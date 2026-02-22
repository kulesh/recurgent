# frozen_string_literal: true

class Agent
  # Agent::SimulationBaselineDiff compares current run evidence against a pinned baseline.
  class SimulationBaselineDiff
    GATE_STATUS_RANK = {
      "fail" => 0,
      "advisory" => 1,
      "not_applicable" => 1,
      "pass" => 2
    }.freeze

    def diff(current_snapshot:, baseline_snapshot:)
      return _no_baseline unless baseline_snapshot

      score_delta = _round(current_snapshot.fetch("overall_score") - baseline_snapshot.fetch("overall_score"))
      gate_deltas = _gate_deltas(current_snapshot.fetch("gate_statuses"), baseline_snapshot.fetch("gate_statuses"))
      classification = _classification(score_delta: score_delta, gate_deltas: gate_deltas)
      {
        "classification" => classification,
        "baseline_run_id" => baseline_snapshot.fetch("run_id"),
        "current_run_id" => current_snapshot.fetch("run_id"),
        "score_delta" => score_delta,
        "gate_deltas" => gate_deltas,
        "non_actionable_noise" => _non_actionable_noise?(classification: classification, gate_deltas: gate_deltas),
        "suspected_causes" => _suspected_causes(score_delta: score_delta, gate_deltas: gate_deltas)
      }
    end

    private

    def _no_baseline
      {
        "classification" => "no_baseline",
        "baseline_run_id" => nil,
        "score_delta" => nil,
        "gate_deltas" => [],
        "non_actionable_noise" => false,
        "suspected_causes" => ["baseline_missing"]
      }
    end

    def _gate_deltas(current, baseline)
      current.keys.sort.map do |gate|
        from_status = baseline.fetch(gate, "not_applicable")
        to_status = current.fetch(gate, "not_applicable")
        {
          "gate" => gate,
          "from" => from_status,
          "to" => to_status,
          "rank_delta" => GATE_STATUS_RANK.fetch(to_status, 0) - GATE_STATUS_RANK.fetch(from_status, 0)
        }
      end
    end

    def _classification(score_delta:, gate_deltas:)
      score_classification = _score_classification(score_delta)
      return score_classification unless score_classification.nil?

      _gate_classification(gate_deltas)
    end

    def _non_actionable_noise?(classification:, gate_deltas:)
      return false unless classification == "unchanged"

      gate_deltas.empty? || gate_deltas.all? { |delta| delta.fetch("rank_delta").zero? }
    end

    def _suspected_causes(score_delta:, gate_deltas:)
      causes = _score_shift_cause(score_delta) + _gate_shift_causes(gate_deltas)
      causes.empty? ? ["no_material_change"] : causes
    end

    def _score_classification(score_delta)
      return "improved" if score_delta > 0.0
      return "regressed" if score_delta < 0.0

      nil
    end

    def _gate_classification(gate_deltas)
      rank_deltas = gate_deltas.map { |delta| delta.fetch("rank_delta") }
      return "improved" if rank_deltas.any?(&:positive?)
      return "regressed" if rank_deltas.any?(&:negative?)

      "unchanged"
    end

    def _score_shift_cause(score_delta)
      score_delta.zero? ? [] : ["score_vector_shift"]
    end

    def _gate_shift_causes(gate_deltas)
      regressed_gates = gate_deltas.select { |delta| delta.fetch("rank_delta").negative? }.map { |delta| delta.fetch("gate") }
      improved_gates = gate_deltas.select { |delta| delta.fetch("rank_delta").positive? }.map { |delta| delta.fetch("gate") }
      causes = []
      causes << "gate_regression:#{regressed_gates.join(",")}" unless regressed_gates.empty?
      causes << "gate_improvement:#{improved_gates.join(",")}" unless improved_gates.empty?
      causes
    end

    def _round(value)
      value.to_f.round(6)
    end
  end
end
