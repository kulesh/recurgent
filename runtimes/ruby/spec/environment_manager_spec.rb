# frozen_string_literal: true

require "spec_helper"
require "digest"
require "json"
require "tmpdir"

RSpec.describe Agent::EnvironmentManager do
  let(:manifest) { [{ name: "nokogiri", version: "~> 1.16" }] }
  let(:cache_root) { Dir.mktmpdir("recurgent-env-manager-") }

  after do
    FileUtils.rm_rf(cache_root)
  end

  it "computes deterministic env_id including RUBY_PLATFORM" do
    manager = described_class.new(
      gem_sources: ["https://rubygems.org"],
      source_mode: "public_only",
      cache_root: cache_root
    )

    expected_payload = [
      "engine:#{RUBY_ENGINE}",
      "ruby:#{RUBY_VERSION}",
      "patchlevel:#{RUBY_PATCHLEVEL}",
      "platform:#{RUBY_PLATFORM}",
      "source_mode:public_only",
      "sources:#{JSON.generate(["https://rubygems.org"])}",
      "deps:#{JSON.generate(manifest)}"
    ].join("|")

    expect(manager.env_id_for(manifest)).to eq(Digest::SHA256.hexdigest(expected_payload))
  end

  it "changes env_id when source policy changes" do
    public_manager = described_class.new(
      gem_sources: ["https://rubygems.org"],
      source_mode: "public_only",
      cache_root: cache_root
    )
    internal_manager = described_class.new(
      gem_sources: ["https://artifactory.example.org/api/gems/ruby"],
      source_mode: "internal_only",
      cache_root: cache_root
    )

    expect(public_manager.env_id_for(manifest)).not_to eq(internal_manager.env_id_for(manifest))
  end

  it "materializes once and returns cache hit on subsequent calls" do
    commands = []
    runner = lambda do |command, env_dir:|
      commands << command
      File.write(File.join(env_dir, "Gemfile.lock"), "GEM\n  specs:\n") if command.include?("lock")
      ["", "", instance_double(Process::Status, success?: true)]
    end

    manager = described_class.new(
      gem_sources: ["https://rubygems.org"],
      source_mode: "public_only",
      cache_root: cache_root,
      command_runner: runner
    )

    first = manager.ensure_environment!(manifest)
    second = manager.ensure_environment!(manifest)

    expect(first[:environment_cache_hit]).to eq(false)
    expect(second[:environment_cache_hit]).to eq(true)
    expect(commands.size).to eq(2)
    expect(commands.map(&:join)).to include(a_string_including("bundlelock"))
    expect(commands.map(&:join)).to include(a_string_including("bundleinstall"))
  end

  it "treats source metadata mismatch as cache miss" do
    commands = []
    runner = lambda do |command, env_dir:|
      commands << command
      File.write(File.join(env_dir, "Gemfile.lock"), "GEM\n  specs:\n") if command.include?("lock")
      ["", "", instance_double(Process::Status, success?: true)]
    end

    manager = described_class.new(
      gem_sources: ["https://rubygems.org"],
      source_mode: "public_only",
      cache_root: cache_root,
      command_runner: runner
    )

    first = manager.ensure_environment!(manifest)
    ready_path = File.join(first.fetch(:env_dir), Agent::EnvironmentManager::READY_FILENAME)
    metadata = JSON.parse(File.read(ready_path))
    metadata["source_mode"] = "internal_only"
    File.write(ready_path, JSON.generate(metadata))

    second = manager.ensure_environment!(manifest)

    expect(first[:environment_cache_hit]).to eq(false)
    expect(second[:environment_cache_hit]).to eq(false)
    expect(commands.size).to eq(4)
  end

  it "raises dependency_resolution_failed on bundle lock failure" do
    runner = lambda do |command, env_dir:|
      _ = env_dir
      if command.include?("lock")
        ["", "lock failed", instance_double(Process::Status, success?: false)]
      else
        ["", "", instance_double(Process::Status, success?: true)]
      end
    end

    manager = described_class.new(
      gem_sources: ["https://rubygems.org"],
      source_mode: "public_only",
      cache_root: cache_root,
      command_runner: runner
    )

    expect do
      manager.ensure_environment!(manifest)
    end.to raise_error(Agent::DependencyResolutionError, /bundle lock failed/)
  end
end
