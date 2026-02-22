# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require "yaml"

class Agent
  # Agent::SimulationRunner executes deterministic and live-shadow simulation packs.
  # rubocop:disable Metrics/ClassLength
  class SimulationRunner
    DEFAULT_MODE = "fixture"
    REQUIRED_GATES = %w[G0 G1 G2 G3 G4 G5].freeze

    # rubocop:disable Metrics/ParameterLists
    def initialize(
      readiness_contract_path: _default_readiness_contract_path,
      fixture_root: _default_fixture_root,
      ledger_path: _default_ledger_path,
      diff_root: _default_diff_root,
      live_shadow_root: _default_live_shadow_root,
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
      @run_scope = Agent::SimulationRunScope.new(root: live_shadow_root)
      @now = now
      @commit_sha = commit_sha.to_s
      @diff_root = diff_root.to_s
      @operational_mode = operational_mode.to_s
      @nightly_trend_report_path = nightly_trend_report_path.to_s
      @gate_definitions = _load_gate_definitions
    end
    # rubocop:enable Metrics/ParameterLists

    def run_pack(pack_path:, mode: nil, session_id: nil, seeds: nil, trace_log_path: nil)
      loaded_pack = Agent::SimulationScenarioPack.load(pack_path)
      run_context = _build_run_context(
        loaded_pack: loaded_pack,
        mode: mode,
        session_id: session_id,
        seeds: seeds,
        trace_log_path: trace_log_path
      )
      entry = _build_ledger_entry(run_context: run_context)
      @ledger.append(entry)
      entry
    end

    private

    def _normalized_seeds(loaded_pack:, override_seeds:)
      seeds = override_seeds || loaded_pack.dig("replay", "seeds") || []
      seeds.map(&:to_i).uniq.sort
    end

    def _execution_lane(loaded_pack:)
      lane = loaded_pack.dig("execution", "lane").to_s
      lane.empty? ? "deterministic" : lane
    end

    def _run_scope_id(execution_lane:, run_id:, session_id:)
      return nil unless execution_lane == "live_shadow"

      "live-shadow:#{session_id}:#{run_id}"
    end

    def _build_run_context(loaded_pack:, mode:, session_id:, seeds:, trace_log_path:)
      execution_lane = _execution_lane(loaded_pack: loaded_pack)
      run_mode = (mode || loaded_pack.dig("replay", "mode") || DEFAULT_MODE).to_s
      seed_list = _normalized_seeds(loaded_pack: loaded_pack, override_seeds: seeds)
      run_id = SecureRandom.hex(12)
      session = _session_id(session_id)
      run_scope_id = _run_scope_id(execution_lane: execution_lane, run_id: run_id, session_id: session)
      per_seed_results = seed_list.map do |seed|
        _run_seed(
          loaded_pack: loaded_pack,
          seed: seed,
          mode: run_mode,
          execution_lane: execution_lane,
          session_id: session,
          run_scope_id: run_scope_id
        )
      end

      {
        run_id: run_id,
        timestamp: @now.call.iso8601,
        session_id: session,
        loaded_pack: loaded_pack,
        execution_lane: execution_lane,
        run_scope_id: run_scope_id,
        usage_telemetry: _usage_telemetry(execution_lane: execution_lane, per_seed_results: per_seed_results),
        mode: run_mode,
        seed_list: seed_list,
        per_seed_results: per_seed_results,
        score: nil,
        prior_entries: @ledger.entries,
        trace_validation: @trace_validator.validate(log_path: trace_log_path)
      }.then { |context| context.merge(score: @scorer.score(loaded_pack: loaded_pack, per_seed_results: context[:per_seed_results])) }
    end

    def _session_id(session_id)
      normalized = session_id.to_s.strip
      normalized.empty? ? SecureRandom.hex(8) : normalized
    end

    def _run_seed(loaded_pack:, seed:, mode:, execution_lane:, session_id:, run_scope_id:)
      run_payload =
        if execution_lane == "live_shadow"
          _compute_live_shadow_seed_payload(
            loaded_pack: loaded_pack,
            seed: seed,
            session_id: session_id,
            run_scope_id: run_scope_id
          )
        else
          _compute_deterministic_seed_payload(loaded_pack: loaded_pack, seed: seed)
        end
      fixture = @fixture_store.read(pack_id: loaded_pack["id"], checksum: loaded_pack["checksum_sha256"], seed: seed)

      case mode
      when "fixture"
        @fixture_store.write(pack_id: loaded_pack["id"], checksum: loaded_pack["checksum_sha256"], seed: seed,
                             payload: run_payload)
        run_payload.merge("replay_match" => true, "fixture_present" => true)
      when "replay"
        replay_match =
          if execution_lane == "live_shadow"
            _live_shadow_replay_match?(current_payload: run_payload, fixture_payload: fixture)
          else
            fixture == run_payload
          end
        run_payload.merge("replay_match" => replay_match, "fixture_present" => !fixture.nil?)
      when "live"
        run_payload.merge("replay_match" => nil, "fixture_present" => !fixture.nil?)
      else
        raise ArgumentError, "unsupported simulation mode: #{mode.inspect}"
      end
    end

    def _compute_deterministic_seed_payload(loaded_pack:, seed:)
      ordered_oracles = _ordered_oracles(loaded_pack.fetch("oracles"), seed: seed)
      oracle_results = ordered_oracles.map do |oracle|
        observation = @oracle.evaluate(oracle, context: {})
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

    def _compute_live_shadow_seed_payload(loaded_pack:, seed:, session_id:, run_scope_id:)
      @run_scope.with_scope(run_scope_id: run_scope_id, seed: seed) do |paths|
        _compute_live_shadow_payload_in_scope(
          loaded_pack: loaded_pack,
          seed: seed,
          session_id: session_id,
          run_scope_id: run_scope_id,
          paths: paths
        )
      end
    end

    def _compute_live_shadow_payload_in_scope(loaded_pack:, seed:, session_id:, run_scope_id:, paths:)
      srand(seed.to_i)
      scenario = loaded_pack.fetch("scenario")
      role = scenario.fetch("role").to_s
      model = scenario.fetch("model", Agent::DEFAULT_MODEL).to_s
      steps = _run_live_shadow_steps(
        role: role,
        model: model,
        script: scenario.fetch("script"),
        trace_log_path: paths.fetch("trace_log_path")
      )
      oracle_results = _run_live_shadow_oracles(
        loaded_pack: loaded_pack,
        seed: seed,
        role: role,
        session_id: session_id,
        steps: steps,
        paths: paths
      )
      {
        "seed" => seed,
        "pack_id" => loaded_pack.fetch("id"),
        "pack_checksum_sha256" => loaded_pack.fetch("checksum_sha256"),
        "execution_lane" => "live_shadow",
        "run_scope_id" => run_scope_id,
        "run_scope_paths" => paths,
        "step_results" => steps,
        "oracle_results" => oracle_results,
        "pass_count" => oracle_results.count { |item| item["passed"] },
        "total_count" => oracle_results.length
      }
    end

    def _run_live_shadow_steps(role:, model:, script:, trace_log_path:)
      agent = Agent.for(role, model: model)
      script.each_with_index.map do |raw_step, index|
        _run_live_shadow_step(
          agent: agent,
          role: role,
          raw_step: raw_step,
          index: index,
          trace_log_path: trace_log_path
        )
      end
    end

    def _run_live_shadow_step(agent:, role:, raw_step:, index:, trace_log_path:)
      step = _normalized_live_shadow_step(raw_step: raw_step, index: index)
      call_name = step.fetch("call")
      args = step.fetch("args")
      kwargs = step.fetch("kwargs")
      step_id = step.fetch("step_id")
      log_entries_before = _read_jsonl(trace_log_path).length
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raw_outcome = _invoke_live_shadow_step(agent: agent, call_name: call_name, args: args, kwargs: kwargs)
      outcome = Agent::Outcome.coerce(raw_outcome, tool_role: role, method_name: call_name)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0).round(3)
      trace_entry = _latest_step_trace_entry(
        trace_log_path: trace_log_path,
        start_index: log_entries_before,
        role: role,
        method_name: call_name
      )

      {
        "step_id" => step_id,
        "step_index" => index,
        "call" => call_name,
        "args" => _json_safe(args),
        "kwargs" => _json_safe(kwargs),
        "duration_ms" => duration_ms,
        "outcome" => _outcome_payload(outcome),
        "trace_ref" => _trace_ref(trace_entry),
        "trace_entry" => trace_entry
      }
    end

    def _normalized_live_shadow_step(raw_step:, index:)
      step = raw_step.transform_keys(&:to_s)
      call_name = step.fetch("call").to_s
      {
        "call" => call_name,
        "args" => Array(step["args"]),
        "kwargs" => _string_keys_hash(step["kwargs"] || {}),
        "step_id" => step.fetch("step_id", "#{call_name}_#{index + 1}").to_s
      }
    end

    def _invoke_live_shadow_step(agent:, call_name:, args:, kwargs:)
      return agent.public_send(call_name, *args) if kwargs.empty?

      symbolized_kwargs = kwargs.transform_keys(&:to_sym)
      agent.public_send(call_name, *args, **symbolized_kwargs)
    rescue StandardError => e
      Agent::Outcome.error(
        error_type: "execution_exception",
        error_message: "#{e.class}: #{e.message}",
        retriable: false
      )
    end

    def _latest_step_trace_entry(trace_log_path:, start_index:, role:, method_name:)
      entries = _read_jsonl(trace_log_path)
      new_entries = entries.drop(start_index)
      scoped = new_entries.select do |entry|
        entry["role"].to_s == role.to_s && entry["method"].to_s == method_name.to_s
      end
      _json_safe(scoped.last || new_entries.last || {})
    end

    def _read_jsonl(path)
      return [] if path.to_s.strip.empty? || !File.exist?(path)

      File.readlines(path).filter_map do |line|
        next if line.to_s.strip.empty?

        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end

    def _run_live_shadow_oracles(loaded_pack:, seed:, role:, session_id:, steps:, paths:)
      ordered_oracles = _ordered_oracles(loaded_pack.fetch("oracles"), seed: seed)
      context = {
        "lane" => "live_shadow",
        "role" => role,
        "seed" => seed,
        "session_id" => session_id,
        "step_results" => steps,
        "trace_log_path" => paths.fetch("trace_log_path")
      }
      ordered_oracles.map do |oracle|
        observation = @oracle.evaluate(oracle, context: context)
        {
          "id" => oracle.fetch("id"),
          "kind" => oracle.fetch("kind"),
          "passed" => observation.fetch("passed"),
          "observation" => observation
        }
      end
    end

    def _live_shadow_replay_match?(current_payload:, fixture_payload:)
      return false unless fixture_payload.is_a?(Hash)

      expected = _oracle_verdict_vector(fixture_payload)
      observed = _oracle_verdict_vector(current_payload)
      expected == observed
    end

    def _oracle_verdict_vector(seed_payload)
      Array(seed_payload["oracle_results"]).map do |item|
        [item["id"].to_s, item["passed"] == true]
      end.sort_by(&:first)
    end

    def _trace_ref(trace_entry)
      {
        "trace_id" => trace_entry["trace_id"],
        "call_id" => trace_entry["call_id"],
        "parent_call_id" => trace_entry["parent_call_id"],
        "depth" => trace_entry["depth"],
        "outcome_status" => trace_entry["outcome_status"]
      }
    end

    def _outcome_payload(outcome)
      {
        "status" => outcome.status.to_s,
        "ok" => outcome.ok?,
        "error_type" => outcome.error_type,
        "error_message" => outcome.error_message,
        "retriable" => outcome.retriable,
        "tool_role" => outcome.tool_role,
        "method_name" => outcome.method_name,
        "value_class" => outcome.value.class.name,
        "value" => _json_safe(outcome.value)
      }
    end

    def _string_keys_hash(hash)
      hash.transform_keys(&:to_s)
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    def _json_safe(value)
      case value
      when Hash
        value.transform_keys(&:to_s).transform_values { |entry| _json_safe(entry) }
      when Array
        value.map { |entry| _json_safe(entry) }
      when Symbol
        value.to_s
      when String, Integer, TrueClass, FalseClass, NilClass
        value
      when Float
        value.finite? ? value : value.to_s
      else
        value.respond_to?(:to_h) ? _json_safe(value.to_h) : value.inspect
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    def _ordered_oracles(oracles, seed:)
      oracles.sort_by { |oracle| Digest::SHA256.hexdigest("#{seed}:#{oracle.fetch("id")}") }
    end

    def _usage_telemetry(execution_lane:, per_seed_results:)
      return _default_usage_telemetry("unknown") if execution_lane != "live_shadow"

      model = _first_live_shadow_model(per_seed_results)
      provider = _provider_for_model(model)
      availability = model.nil? ? "unavailable" : "partial"
      _default_usage_telemetry(availability).merge(
        "provider" => provider,
        "model" => model
      )
    end

    def _default_usage_telemetry(availability)
      {
        "provider" => nil,
        "model" => nil,
        "input_tokens" => nil,
        "output_tokens" => nil,
        "total_tokens" => nil,
        "estimated_cost_usd" => nil,
        "availability" => availability
      }
    end

    def _first_live_shadow_model(per_seed_results)
      per_seed_results.each do |seed_result|
        Array(seed_result["step_results"]).each do |step|
          model = step.dig("trace_entry", "model")
          return model.to_s unless model.to_s.empty?
        end
      end
      nil
    end

    def _provider_for_model(model)
      return nil if model.to_s.empty?

      model.to_s.match?(Agent::OPENAI_MODEL_PATTERN) ? "openai" : "anthropic"
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
        "execution_lane" => run_context.fetch(:execution_lane),
        "run_scope_id" => run_context.fetch(:run_scope_id),
        "seed" => run_context.fetch(:seed_list).first,
        "session_id" => run_context.fetch(:session_id),
        "mode" => run_context.fetch(:mode),
        "score_vector" => score.fetch("weighted").merge("overall" => score.fetch("overall")),
        "scorer_version" => score.fetch("scorer_version"),
        "artifacts" => {
          "scenario_pack_checksum_sha256" => loaded_pack.fetch("checksum_sha256"),
          "baseline_diff_report_path" => run_context.fetch(:baseline_diff_path)
        },
        "usage_telemetry" => run_context.fetch(:usage_telemetry),
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
      execution_lane = run_context.fetch(:execution_lane)
      run_context.fetch(:prior_entries).reverse.find do |entry|
        entry["scenario_pack_id"] == pack_id &&
          entry["execution_lane"].to_s == execution_lane &&
          entry["mode"] == "replay" &&
          Array(entry.dig("metrics", "seeds")) == seed_list &&
          entry["scorer_version"] == scorer_version
      end
    end

    def _baseline_snapshot(run_context:)
      pack_id = run_context.fetch(:loaded_pack).fetch("id")
      mode = run_context.fetch(:mode)
      seed_list = run_context.fetch(:seed_list)
      execution_lane = run_context.fetch(:execution_lane)
      entry = run_context.fetch(:prior_entries).reverse.find do |candidate|
        candidate["scenario_pack_id"] == pack_id &&
          candidate["execution_lane"].to_s == execution_lane &&
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

    def _default_live_shadow_root
      File.expand_path("../../../../tmp/simulation/live-shadow", __dir__)
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
