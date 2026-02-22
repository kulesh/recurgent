# frozen_string_literal: true

require "fileutils"
require "tmpdir"

class Agent
  # Agent::SimulationRunScope manages per-run/per-seed runtime isolation roots.
  class SimulationRunScope
    def initialize(root:)
      @root = root.to_s
    end

    def with_scope(run_scope_id:, seed:)
      paths = _build_scope_paths(run_scope_id: run_scope_id, seed: seed)
      _prepare_scope_paths!(paths)
      _with_runtime_scope(paths) { yield(paths) }
    end

    private

    attr_reader :root

    def _build_scope_paths(run_scope_id:, seed:)
      scope_segment = _safe_segment(run_scope_id)
      seed_segment = "seed-#{seed.to_i}"
      scope_root = File.join(root, scope_segment, seed_segment)
      state_home = File.join(scope_root, "state")
      toolstore_root = File.join(scope_root, "toolstore")
      temp_root = File.join(scope_root, "tmp")
      {
        "root" => scope_root,
        "state_home" => state_home,
        "toolstore_root" => toolstore_root,
        "tmp_root" => temp_root,
        "trace_log_path" => File.join(state_home, "recurgent", "recurgent.jsonl")
      }
    end

    def _prepare_scope_paths!(paths)
      FileUtils.mkdir_p(paths.fetch("root"))
      FileUtils.mkdir_p(paths.fetch("state_home"))
      FileUtils.mkdir_p(paths.fetch("toolstore_root"))
      FileUtils.mkdir_p(paths.fetch("tmp_root"))
    end

    def _with_runtime_scope(paths)
      previous_runtime_config = _deep_dup_hash(Agent.runtime_config)
      previous_env = {
        "XDG_STATE_HOME" => ENV.fetch("XDG_STATE_HOME", nil),
        "RECURGENT_TOOLSTORE_ROOT" => ENV.fetch("RECURGENT_TOOLSTORE_ROOT", nil),
        "TMPDIR" => ENV.fetch("TMPDIR", nil)
      }
      _apply_scope_environment!(paths)
      yield
    ensure
      _restore_environment!(previous_env)
      Agent.instance_variable_set(:@runtime_config, previous_runtime_config)
    end

    def _apply_scope_environment!(paths)
      Agent.reset_runtime_config!
      ENV["XDG_STATE_HOME"] = paths.fetch("state_home")
      ENV["RECURGENT_TOOLSTORE_ROOT"] = paths.fetch("toolstore_root")
      ENV["TMPDIR"] = paths.fetch("tmp_root")
      Agent.configure_runtime(toolstore_root: paths.fetch("toolstore_root"))
    end

    def _restore_environment!(previous_env)
      Agent.reset_runtime_config!
      previous_env.each do |key, value|
        if value.nil?
          ENV.delete(key)
        else
          ENV[key] = value
        end
      end
    end

    def _safe_segment(value)
      raw = value.to_s.strip.downcase
      sanitized = +""
      dash_open = false

      raw.each_char do |char|
        if char.between?("a", "z") || char.between?("0", "9")
          sanitized << char
          dash_open = false
        elsif !dash_open
          sanitized << "-"
          dash_open = true
        end
      end

      sanitized.delete_prefix!("-")
      sanitized.delete_suffix!("-")
      sanitized
    end

    def _deep_dup_hash(payload)
      Marshal.load(Marshal.dump(payload))
    end
  end
end
