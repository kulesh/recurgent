# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require "yaml"

class Agent
  # Agent::SimulationRunner executes deterministic class-1 packs in fixture/replay/live modes.
  # rubocop:disable Metrics/ClassLength
  class SimulationRunner
    DEFAULT_MODE = "fixture"
    REQUIRED_GATES = %w[G0 G1 G2 G3 G4 G5].freeze

    def initialize(
      readiness_contract_path: _default_readiness_contract_path,
      fixture_root: _default_fixture_root,
      ledger_path: _default_ledger_path,
      diff_root: _default_diff_root,
      operational_mode: _default_operational_mode,
      nightly_trend_report_path: _default_nightly_trend_report_path,
      now: -> { Time.now.utc },
      commit_sha: _default_commit_sha
    )
      @readiness_contract_path = readiness_contract_path.to_s
      @fixture_store = Agent::SimulationFixtureStore.new(root: fixture_root)
      @ledger = Agent::SimulationRunLedger.new(path: ledger_path)
      @oracle = Agent::SimulationCalculatorOracle.new
      @scorer = Agent::SimulationScorer.new
      @trace_validator = Agent::SimulationTraceSchemaValidator.new
      @baseline_diff = Agent::SimulationBaselineDiff.new
      @now = now
      @commit_sha = commit_sha.to_s
      @diff_root = diff_root.to_s
      @operational_mode = operational_mode.to_s
      @nightly_trend_report_path = nightly_trend_report_path.to_s
      @gate_definitions = _load_gate_definitions
    end

    def run_pack(pack_path:, mode: nil, session_id: nil, seeds: nil, trace_log_path: nil)
      loaded_pack = Agent::SimulationScenarioPack.load(pack_path)
      run_mode = (mode || loaded_pack.dig("replay", "mode") || DEFAULT_MODE).to_s
      seed_list = _normalized_seeds(loaded_pack: loaded_pack, override_seeds: seeds)
      run_id = SecureRandom.hex(12)
      session = session_id.to_s.strip.empty? ? SecureRandom.hex(8) : session_id.to_s
      trace_validation = @trace_validator.validate(log_path: trace_log_path)

      per_seed_results = seed_list.map { |seed| _run_seed(loaded_pack: loaded_pack, seed: seed, mode: run_mode) }
      score = @scorer.score(loaded_pack: loaded_pack, per_seed_results: per_seed_results)
      prior_entries = @ledger.entries

      entry = _build_ledger_entry(
        run_context: {
          run_id: run_id,
          timestamp: @now.call.iso8601,
          session_id: session,
          loaded_pack: loaded_pack,
          mode: run_mode,
          seed_list: seed_list,
          per_seed_results: per_seed_results,
          score: score,
          prior_entries: prior_entries,
          trace_validation: trace_validation
        }
      )
      @ledger.append(entry)
      entry
    end

    private

    def _normalized_seeds(loaded_pack:, override_seeds:)
      seeds = override_seeds || loaded_pack.dig("replay", "seeds") || []
      seeds.map(&:to_i).uniq.sort
    end

    def _run_seed(loaded_pack:, seed:, mode:)
      run_payload = _compute_seed_payload(loaded_pack: loaded_pack, seed: seed)
      fixture = @fixture_store.read(pack_id: loaded_pack["id"], checksum: loaded_pack["checksum_sha256"], seed: seed)

      case mode
      when "fixture"
        @fixture_store.write(pack_id: loaded_pack["id"], checksum: loaded_pack["checksum_sha256"], seed: seed,
                             payload: run_payload)
        run_payload.merge("replay_match" => true, "fixture_present" => true)
      when "replay"
        run_payload.merge("replay_match" => fixture == run_payload, "fixture_present" => !fixture.nil?)
      when "live"
        run_payload.merge("replay_match" => nil, "fixture_present" => !fixture.nil?)
      else
        raise ArgumentError, "unsupported simulation mode: #{mode.inspect}"
      end
    end

    def _compute_seed_payload(loaded_pack:, seed:)
      ordered_oracles = _ordered_oracles(loaded_pack.fetch("oracles"), seed: seed)
      oracle_results = ordered_oracles.map do |oracle|
        observation = @oracle.evaluate(oracle)
        {
          "id" => oracle.fetch("id"),
          "kind" => oracle.fetch("kind"),
          "passed" => observation.fetch("passed"),
          "observation" => observation
        }
      end
      {
        "seed" => seed,
        "pack_id" => loaded_pack.fetch("id"),
        "pack_checksum_sha256" => loaded_pack.fetch("checksum_sha256"),
        "oracle_results" => oracle_results,
        "pass_count" => oracle_results.count { |item| item["passed"] },
        "total_count" => oracle_results.length
      }
    end

    def _ordered_oracles(oracles, seed:)
      oracles.sort_by { |oracle| Digest::SHA256.hexdigest("#{seed}:#{oracle.fetch("id")}") }
    end

    def _build_ledger_entry(run_context:)
      replay_stability = _replay_stability(run_context.fetch(:per_seed_results))
      score_state = _score_reproducibility_state(run_context: run_context)
      baseline_snapshot = _baseline_snapshot(run_context: run_context)
      current_snapshot = _current_snapshot(run_context: run_context, replay_stability: replay_stability, score_state: score_state)
      baseline_diff_report = @baseline_diff.diff(current_snapshot: current_snapshot, baseline_snapshot: baseline_snapshot)
      baseline_diff_path = _write_baseline_diff_report(run_id: run_context.fetch(:run_id), diff_report: baseline_diff_report)

      gates = _build_gate_results(
        mode: run_context.fetch(:mode),
        replay_stability: replay_stability,
        score_state: score_state,
        trace_validation: run_context.fetch(:trace_validation),
        baseline_diff_report: baseline_diff_report
      )
      _ledger_entry_payload(
        run_context: run_context.merge(
          replay_stability: replay_stability,
          baseline_diff_report: baseline_diff_report,
          baseline_diff_path: baseline_diff_path
        ),
        gates: gates
      )
    end

    def _ledger_entry_payload(run_context:, gates:)
      loaded_pack = run_context.fetch(:loaded_pack)
      score = run_context.fetch(:score)
      {
        "schema_version" => 1,
        "run_id" => run_context.fetch(:run_id),
        "recorded_at" => run_context.fetch(:timestamp),
        "commit_sha" => @commit_sha,
        "scenario_pack_id" => loaded_pack.fetch("id"),
        "scenario_class" => loaded_pack.fetch("class"),
        "seed" => run_context.fetch(:seed_list).first,
        "session_id" => run_context.fetch(:session_id),
        "mode" => run_context.fetch(:mode),
        "score_vector" => score.fetch("weighted").merge("overall" => score.fetch("overall")),
        "scorer_version" => score.fetch("scorer_version"),
        "artifacts" => {
          "scenario_pack_checksum_sha256" => loaded_pack.fetch("checksum_sha256"),
          "baseline_diff_report_path" => run_context.fetch(:baseline_diff_path)
        },
        "metrics" => _metrics_payload(run_context: run_context),
        "gates" => gates
      }
    end

    def _metrics_payload(run_context:)
      score = run_context.fetch(:score)
      {
        "seeds" => run_context.fetch(:seed_list),
        "replay_stability" => run_context.fetch(:replay_stability),
        "per_seed_results" => run_context.fetch(:per_seed_results),
        "score_components" => score.fetch("components"),
        "score_weights" => score.fetch("weights"),
        "trace_validation" => run_context.fetch(:trace_validation),
        "baseline_diff_report" => run_context.fetch(:baseline_diff_report)
      }
    end

    def _replay_stability(per_seed_results)
      replay_matches = per_seed_results.map { |result| result["replay_match"] }.compact
      return nil if replay_matches.empty?

      replay_matches.count(true).to_f / replay_matches.length
    end

    def _build_gate_results(mode:, replay_stability:, score_state:, trace_validation:, baseline_diff_report:)
      REQUIRED_GATES.each_with_object({}) do |gate_id, results|
        results[gate_id] = _gate_result_for(
          gate_id,
          mode: mode,
          replay_stability: replay_stability,
          score_state: score_state,
          trace_validation: trace_validation,
          baseline_diff_report: baseline_diff_report
        )
      end
    end

    def _gate_result_for(gate_id, mode:, replay_stability:, score_state:, trace_validation:, baseline_diff_report:)
      definition = @gate_definitions.fetch(gate_id)
      status, message = _gate_status_and_message(
        gate_id,
        mode: mode,
        replay_stability: replay_stability,
        score_state: score_state,
        trace_validation: trace_validation,
        baseline_diff_report: baseline_diff_report,
        operational_mode: @operational_mode,
        nightly_trend_report_path: @nightly_trend_report_path
      )
      {
        "status" => status,
        "evaluator_owner" => definition.fetch("evaluator_owner"),
        "required_artifacts" => definition.fetch("required_artifacts"),
        "message" => message,
        "measured_at" => @now.call.iso8601
      }
    end

    def _gate_status_and_message(gate_id, mode:, replay_stability:, score_state:, trace_validation:, baseline_diff_report:,
                                 operational_mode:, nightly_trend_report_path:)
      return ["pass", "scenario pack contract validated"] if gate_id == "G0"
      return _g1_status(mode: mode, replay_stability: replay_stability) if gate_id == "G1"
      return _g2_status(mode: mode, score_state: score_state) if gate_id == "G2"
      return _g3_status(trace_validation: trace_validation) if gate_id == "G3"
      return _g4_status(baseline_diff_report: baseline_diff_report) if gate_id == "G4"
      return _g5_status(operational_mode: operational_mode, nightly_trend_report_path: nightly_trend_report_path) if gate_id == "G5"

      ["not_applicable", "gate not implemented in this phase"]
    end

    def _g1_status(mode:, replay_stability:)
      return ["advisory", "replayability measured in replay mode"] unless mode == "replay"

      replay_ok = !replay_stability.nil? && replay_stability >= 0.99
      [replay_ok ? "pass" : "fail", "replay stability=#{(replay_stability || 0.0).round(4)}"]
    end

    def _g2_status(mode:, score_state:)
      return ["advisory", "score consistency measured in replay mode"] unless mode == "replay"

      case score_state
      when :match
        ["pass", "score vector reproducible against prior replay entry"]
      when :drift
        ["fail", "score vector drift detected for same replay config"]
      else
        ["advisory", "no prior replay entry for score reproducibility comparison"]
      end
    end

    def _g3_status(trace_validation:)
      return ["advisory", "trace validation skipped: no trace log provided"] if trace_validation["valid"].nil?
      return ["pass", "trace schema validation passed (entries=#{trace_validation["entry_count"]})"] if trace_validation["valid"]

      message = "trace schema validation failed at #{trace_validation["first_invalid_field_path"]} " \
                "(entry #{trace_validation["first_invalid_entry_index"]}): #{trace_validation["first_invalid_reason"]}"
      ["fail", message]
    end

    def _g4_status(baseline_diff_report:)
      classification = baseline_diff_report["classification"].to_s
      return ["fail", "baseline diff report missing classification"] if classification.empty?

      ["pass", "baseline diff classification=#{classification}"]
    end

    def _g5_status(operational_mode:, nightly_trend_report_path:)
      case operational_mode
      when "ci"
        ["pass", "ci readiness gate executed"]
      when "nightly"
        return ["fail", "nightly trend report path missing"] if nightly_trend_report_path.strip.empty?

        ["pass", "nightly readiness run configured (trend_report=#{nightly_trend_report_path})"]
      else
        ["not_applicable", "gate not implemented in this phase"]
      end
    end

    def _score_reproducibility_state(run_context:)
      mode = run_context.fetch(:mode)
      return :not_replay unless mode == "replay"

      comparable = _find_comparable_replay_entry(run_context: run_context)
      return :no_baseline unless comparable

      score = run_context.fetch(:score)
      expected = score.fetch("weighted").merge("overall" => score.fetch("overall"))
      comparable["score_vector"] == expected ? :match : :drift
    end

    def _find_comparable_replay_entry(run_context:)
      pack_id = run_context.fetch(:loaded_pack).fetch("id")
      seed_list = run_context.fetch(:seed_list)
      scorer_version = run_context.fetch(:score).fetch("scorer_version")
      run_context.fetch(:prior_entries).reverse.find do |entry|
        entry["scenario_pack_id"] == pack_id &&
          entry["mode"] == "replay" &&
          Array(entry.dig("metrics", "seeds")) == seed_list &&
          entry["scorer_version"] == scorer_version
      end
    end

    def _baseline_snapshot(run_context:)
      pack_id = run_context.fetch(:loaded_pack).fetch("id")
      mode = run_context.fetch(:mode)
      seed_list = run_context.fetch(:seed_list)
      entry = run_context.fetch(:prior_entries).reverse.find do |candidate|
        candidate["scenario_pack_id"] == pack_id &&
          candidate["mode"] == mode &&
          Array(candidate.dig("metrics", "seeds")) == seed_list
      end
      return nil unless entry

      {
        "run_id" => entry.fetch("run_id"),
        "overall_score" => entry.fetch("score_vector").fetch("overall").to_f,
        "gate_statuses" => _gate_status_map(entry.fetch("gates"))
      }
    end

    def _current_snapshot(run_context:, replay_stability:, score_state:)
      provisional_gates = _build_gate_results(
        mode: run_context.fetch(:mode),
        replay_stability: replay_stability,
        score_state: score_state,
        trace_validation: run_context.fetch(:trace_validation),
        baseline_diff_report: { "classification" => "provisional" }
      )
      {
        "run_id" => run_context.fetch(:run_id),
        "overall_score" => run_context.fetch(:score).fetch("overall").to_f,
        "gate_statuses" => _gate_status_map(provisional_gates)
      }
    end

    def _gate_status_map(gates)
      gates.transform_values { |details| details.fetch("status") }
    end

    def _write_baseline_diff_report(run_id:, diff_report:)
      FileUtils.mkdir_p(@diff_root)
      path = File.join(@diff_root, "#{run_id}.json")
      File.write(path, JSON.pretty_generate(diff_report))
      path
    end

    def _load_gate_definitions
      payload = YAML.safe_load_file(@readiness_contract_path, permitted_classes: [], permitted_symbols: [], aliases: false)
      gates = payload.fetch("simulation_preparedness").fetch("gates")
      gates.transform_values do |gate|
        {
          "evaluator_owner" => gate.fetch("evaluator_owner").to_s,
          "required_artifacts" => Array(gate.fetch("required_artifacts")).map(&:to_s)
        }
      end
    end

    def _default_readiness_contract_path
      File.expand_path("../../../../specs/contract/v1/simulation-preparedness.contract.yaml", __dir__)
    end

    def _default_fixture_root
      File.expand_path("../../../../tmp/simulation/fixtures", __dir__)
    end

    def _default_ledger_path
      File.expand_path("../../../../tmp/simulation/run-ledger.jsonl", __dir__)
    end

    def _default_diff_root
      File.expand_path("../../../../tmp/simulation/diffs", __dir__)
    end

    def _default_commit_sha
      sha = `git rev-parse --short HEAD`.strip
      sha.empty? ? "unknown0000000" : sha
    rescue StandardError
      "unknown0000000"
    end

    def _default_operational_mode
      return "ci" if ENV["CI"].to_s == "true"

      "local"
    end

    def _default_nightly_trend_report_path
      ENV["RECURGENT_SIM_NIGHTLY_TREND_REPORT"].to_s
    end
  end
  # rubocop:enable Metrics/ClassLength
end
