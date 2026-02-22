# frozen_string_literal: true

require "time"

class Agent
  # Agent::SimulationAdvisoryStatus aggregates class-2+ simulation evidence for advisory reporting.
  class SimulationAdvisoryStatus
    def initialize(ledger_path:, pack_ids: nil)
      @ledger = Agent::SimulationRunLedger.new(path: ledger_path)
      @pack_ids = Array(pack_ids).map(&:to_s).reject(&:empty?)
    end

    def analyze
      replay_entries = @ledger.entries.select { |entry| entry["mode"] == "replay" && entry["scenario_class"] == "class_2_plus" }
      replay_entries = replay_entries.select { |entry| @pack_ids.include?(entry["scenario_pack_id"]) } unless @pack_ids.empty?

      grouped = replay_entries.group_by { |entry| entry.fetch("scenario_pack_id", "unknown") }
      summaries = grouped.keys.sort.map { |pack_id| _pack_summary(pack_id: pack_id, entries: grouped.fetch(pack_id)) }

      {
        "generated_at" => Time.now.utc.iso8601,
        "pack_count" => summaries.length,
        "total_replay_runs" => replay_entries.length,
        "pack_summaries" => summaries,
        "global_failure_signatures" => _global_failure_signatures(summaries)
      }
    end

    private

    def _pack_summary(pack_id:, entries:)
      ordered = entries.sort_by { |entry| _safe_time(entry["recorded_at"]).to_i }
      latest = ordered.last

      {
        "pack_id" => pack_id,
        "scenario_class" => latest.fetch("scenario_class", "class_2_plus"),
        "run_count" => ordered.length,
        "seed_set" => _seed_set(ordered),
        "latest_recorded_at" => latest["recorded_at"],
        "latest_gate_statuses" => _gate_statuses(latest),
        "score_trend" => _score_trend(ordered),
        "failure_signatures" => _failure_signatures(ordered)
      }
    end

    def _seed_set(entries)
      entries.flat_map { |entry| Array(entry.dig("metrics", "seeds")) }.map(&:to_i).uniq.sort
    end

    def _score_trend(entries)
      score_series = entries.map { |entry| entry.dig("score_vector", "overall").to_f }
      {
        "first" => score_series.first,
        "latest" => score_series.last,
        "min" => score_series.min,
        "max" => score_series.max,
        "delta" => (score_series.last - score_series.first).round(6)
      }
    end

    def _gate_statuses(entry)
      entry.fetch("gates", {}).transform_values { |details| details.fetch("status", "not_applicable") }
    end

    def _failure_signatures(entries)
      counts = Hash.new(0)

      entries.each do |entry|
        _gate_statuses(entry).each do |gate, status|
          next if status == "pass"

          counts["gate:#{gate}=#{status}"] += 1
        end

        classification = entry.dig("metrics", "baseline_diff_report", "classification").to_s
        counts["baseline_diff:#{classification}"] += 1 unless classification.empty? || classification == "improved"
      end

      counts.keys.sort.map do |signature|
        {
          "signature" => signature,
          "count" => counts.fetch(signature)
        }
      end
    end

    def _global_failure_signatures(summaries)
      counts = Hash.new(0)
      summaries.each do |summary|
        Array(summary["failure_signatures"]).each do |item|
          counts[item.fetch("signature")] += item.fetch("count").to_i
        end
      end

      counts.keys.sort.map do |signature|
        {
          "signature" => signature,
          "count" => counts.fetch(signature)
        }
      end
    end

    def _safe_time(value)
      Time.parse(value.to_s).utc
    rescue StandardError
      Time.at(0).utc
    end
  end
end
