# frozen_string_literal: true

require "time"

class Agent
  # Agent::SimulationStabilizationWindow evaluates class-1 observation-window progress.
  class SimulationStabilizationWindow
    DEFAULT_REQUIRED_PACKS = %w[calculator-core-v1 calculator-edge-v1].freeze
    DEFAULT_REQUIRED_GATES = %w[G0 G1 G2 G3 G4 G5].freeze

    def initialize(
      ledger_path:,
      required_runs: 20,
      min_seed_count: 5,
      min_session_count: 2,
      min_day_count: 3,
      required_packs: DEFAULT_REQUIRED_PACKS,
      required_gates: DEFAULT_REQUIRED_GATES
    )
      @ledger = Agent::SimulationRunLedger.new(path: ledger_path)
      @required_runs = required_runs.to_i
      @min_seed_count = min_seed_count.to_i
      @min_session_count = min_session_count.to_i
      @min_day_count = min_day_count.to_i
      @required_packs = Array(required_packs).map(&:to_s).uniq.sort
      @required_gates = Array(required_gates).map(&:to_s).uniq.sort
    end

    def analyze
      replay_entries = _replay_entries_with_ordinal
      session_records = _session_records(replay_entries)
      observed = _observed_metrics(session_records)

      {
        "window_requirements" => {
          "required_runs" => @required_runs,
          "min_seed_count" => @min_seed_count,
          "min_session_count" => @min_session_count,
          "min_day_count" => @min_day_count,
          "required_packs" => @required_packs,
          "required_gates" => @required_gates
        },
        "observed" => observed,
        "window_met" => _window_met?(
          trailing_consecutive: observed.fetch("trailing_consecutive_qualifying"),
          distinct_seed_count: observed.fetch("distinct_seed_count"),
          qualifying_session_count: observed.fetch("qualifying_session_count"),
          distinct_day_count: observed.fetch("distinct_day_count")
        ),
        "reset_events" => session_records.reject { |record| record.fetch("qualifying") }.map do |record|
          {
            "session_id" => record.fetch("session_id"),
            "recorded_at" => record.fetch("recorded_at"),
            "reasons" => record.fetch("reasons")
          }
        end,
        "session_records" => session_records
      }
    end

    private

    def _observed_metrics(session_records)
      qualifying_records = session_records.select { |record| record.fetch("qualifying") }
      {
        "session_count" => session_records.length,
        "qualifying_session_count" => qualifying_records.length,
        "trailing_consecutive_qualifying" => _trailing_consecutive_qualifying(session_records),
        "distinct_seed_count" => qualifying_records.flat_map { |record| record.fetch("seeds") }.uniq.length,
        "distinct_day_count" => qualifying_records.map { |record| record.fetch("day") }.compact.uniq.length
      }
    end

    def _replay_entries_with_ordinal
      @ledger.entries.each_with_index.filter_map do |entry, ordinal|
        next unless entry["mode"] == "replay"

        entry.merge("__ordinal" => ordinal)
      end
    end

    def _session_records(entries)
      grouped = entries.group_by { |entry| entry.fetch("session_id", "") }
      grouped.keys.sort_by { |session_id| _session_sort_key(grouped.fetch(session_id)) }.map do |session_id|
        session_entries = grouped.fetch(session_id)
        _build_session_record(session_id: session_id, session_entries: session_entries)
      end
    end

    def _session_sort_key(entries)
      entries.map { |entry| entry.fetch("__ordinal") }.min || 0
    end

    def _build_session_record(session_id:, session_entries:)
      latest_by_pack = _latest_entries_by_pack(session_entries)
      reasons = _missing_pack_reasons(latest_by_pack)
      pack_gate_statuses, gate_failure_reasons = _pack_statuses_and_gate_failure_reasons(latest_by_pack)
      reasons.concat(gate_failure_reasons)

      recorded_at = _latest_recorded_at(latest_by_pack.values.compact)
      {
        "session_id" => session_id,
        "recorded_at" => recorded_at,
        "day" => _day_of(recorded_at),
        "seeds" => latest_by_pack.values.compact.flat_map { |entry| Array(entry.dig("metrics", "seeds")).map(&:to_i) }.uniq.sort,
        "pack_gate_statuses" => pack_gate_statuses,
        "qualifying" => reasons.empty?,
        "reasons" => reasons
      }
    end

    def _latest_entries_by_pack(session_entries)
      by_pack = session_entries.group_by { |entry| entry.fetch("scenario_pack_id", "") }
      by_pack.transform_values { |entries| entries.max_by { |entry| entry.fetch("__ordinal") } }
    end

    def _missing_pack_reasons(latest_by_pack)
      missing_packs = @required_packs - latest_by_pack.keys
      return [] if missing_packs.empty?

      ["missing_required_packs:#{missing_packs.join(",")}"]
    end

    def _pack_statuses_and_gate_failure_reasons(latest_by_pack)
      statuses = {}
      reasons = []

      @required_packs.each do |pack_id|
        entry = latest_by_pack[pack_id]
        next unless entry

        gate_statuses = _gate_statuses(entry)
        statuses[pack_id] = gate_statuses
        failed_gates = @required_gates.reject { |gate| gate_statuses[gate] == "pass" }
        reasons << "gate_failures:#{pack_id}:#{failed_gates.join(",")}" unless failed_gates.empty?
      end

      [statuses, reasons]
    end

    def _gate_statuses(entry)
      gates = entry.fetch("gates", {})
      @required_gates.each_with_object({}) do |gate, statuses|
        statuses[gate] = gates.dig(gate, "status").to_s
      end
    end

    def _latest_recorded_at(entries)
      entries.map { |entry| entry.fetch("recorded_at", "").to_s }.max.to_s
    end

    def _day_of(timestamp)
      return nil if timestamp.to_s.empty?

      Time.parse(timestamp).utc.strftime("%Y-%m-%d")
    rescue ArgumentError
      nil
    end

    def _trailing_consecutive_qualifying(session_records)
      count = 0
      session_records.reverse_each do |record|
        break unless record.fetch("qualifying")

        count += 1
      end
      count
    end

    def _window_met?(trailing_consecutive:, distinct_seed_count:, qualifying_session_count:, distinct_day_count:)
      trailing_consecutive >= @required_runs &&
        distinct_seed_count >= @min_seed_count &&
        qualifying_session_count >= @min_session_count &&
        distinct_day_count >= @min_day_count
    end
  end
end
