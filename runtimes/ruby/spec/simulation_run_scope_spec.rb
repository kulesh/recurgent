# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Agent::SimulationRunScope do
  let(:tmpdir) { Dir.mktmpdir("recurgent-sim-scope-") }
  let(:scope_root) { File.join(tmpdir, "live-shadow") }
  let(:scope) { described_class.new(root: scope_root) }

  after do
    FileUtils.remove_entry(tmpdir) if tmpdir && File.exist?(tmpdir)
    Agent.reset_runtime_config!
  end

  it "builds isolated roots per run scope and seed" do
    scope.with_scope(run_scope_id: "session-a:run-1", seed: 11) do |paths_a|
      File.write(File.join(paths_a.fetch("toolstore_root"), "marker-a.txt"), "a")
      File.write(File.join(paths_a.fetch("state_home"), "marker-a.txt"), "a")
      File.write(File.join(paths_a.fetch("tmp_root"), "marker-a.txt"), "a")

      expect(Agent.runtime_config[:toolstore_root]).to eq(paths_a.fetch("toolstore_root"))
      expect(ENV.fetch("XDG_STATE_HOME", nil)).to eq(paths_a.fetch("state_home"))
      expect(ENV.fetch("TMPDIR", nil)).to eq(paths_a.fetch("tmp_root"))
    end

    scope.with_scope(run_scope_id: "session-a:run-2", seed: 11) do |paths_b|
      expect(File.exist?(File.join(paths_b.fetch("toolstore_root"), "marker-a.txt"))).to eq(false)
      expect(File.exist?(File.join(paths_b.fetch("state_home"), "marker-a.txt"))).to eq(false)
      expect(File.exist?(File.join(paths_b.fetch("tmp_root"), "marker-a.txt"))).to eq(false)
    end
  end

  it "restores runtime config and environment after scoped run" do
    original_state_home = ENV.fetch("XDG_STATE_HOME", nil)
    original_tmpdir = ENV.fetch("TMPDIR", nil)
    Agent.configure_runtime(toolstore_root: File.join(tmpdir, "global-toolstore"))
    previous_runtime = Agent.runtime_config.dup

    scope.with_scope(run_scope_id: "session-a:run-3", seed: 19) do |paths|
      expect(Agent.runtime_config[:toolstore_root]).to eq(paths.fetch("toolstore_root"))
      expect(ENV.fetch("XDG_STATE_HOME", nil)).to eq(paths.fetch("state_home"))
    end

    expect(Agent.runtime_config[:toolstore_root]).to eq(previous_runtime[:toolstore_root])
    expect(ENV.fetch("XDG_STATE_HOME", nil)).to eq(original_state_home)
    expect(ENV.fetch("TMPDIR", nil)).to eq(original_tmpdir)
  end
end
