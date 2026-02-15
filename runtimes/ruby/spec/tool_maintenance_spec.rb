# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require "fileutils"

RSpec.describe Agent::ToolMaintenance do
  def write_registry(path, payload)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(payload))
  end

  it "lists stale tools by last_used_at cutoff" do
    Dir.mktmpdir("recurgent-maintenance-") do |tmpdir|
      registry_path = File.join(tmpdir, "registry.json")
      now = Time.now.utc
      write_registry(
        registry_path,
        {
          schema_version: Agent::TOOLSTORE_SCHEMA_VERSION,
          tools: {
            "fresh_tool" => {
              purpose: "fresh",
              last_used_at: now.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
            },
            "stale_tool" => {
              purpose: "stale",
              last_used_at: (now - (45 * 86_400)).strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
            }
          }
        }
      )

      maintenance = described_class.new(toolstore_root: tmpdir)
      stale = maintenance.list_stale_tools(stale_days: 30)
      names = stale.map { |entry| entry.fetch("name") }
      expect(names).to include("stale_tool")
      expect(names).not_to include("fresh_tool")
    end
  end

  it "supports prune dry-run without mutating registry" do
    Dir.mktmpdir("recurgent-maintenance-") do |tmpdir|
      registry_path = File.join(tmpdir, "registry.json")
      write_registry(
        registry_path,
        {
          schema_version: Agent::TOOLSTORE_SCHEMA_VERSION,
          tools: {
            "stale_tool" => {
              purpose: "stale",
              last_used_at: (Time.now.utc - (60 * 86_400)).strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
            }
          }
        }
      )

      maintenance = described_class.new(toolstore_root: tmpdir)
      summary = maintenance.prune_stale_tools(stale_days: 30, dry_run: true, mode: "archive")
      expect(summary.fetch("dry_run")).to eq(true)
      expect(summary.fetch("pruned_count")).to eq(1)

      persisted = JSON.parse(File.read(registry_path))
      expect(persisted.fetch("tools")).to have_key("stale_tool")
      expect(persisted["archived_tools"]).to be_nil
    end
  end

  it "archives stale tools when prune is applied in archive mode" do
    Dir.mktmpdir("recurgent-maintenance-") do |tmpdir|
      registry_path = File.join(tmpdir, "registry.json")
      write_registry(
        registry_path,
        {
          schema_version: Agent::TOOLSTORE_SCHEMA_VERSION,
          tools: {
            "stale_tool" => {
              purpose: "stale",
              last_used_at: (Time.now.utc - (60 * 86_400)).strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
            }
          }
        }
      )

      maintenance = described_class.new(toolstore_root: tmpdir)
      summary = maintenance.prune_stale_tools(stale_days: 30, dry_run: false, mode: "archive")
      expect(summary.fetch("dry_run")).to eq(false)
      expect(summary.fetch("pruned_count")).to eq(1)

      persisted = JSON.parse(File.read(registry_path))
      expect(persisted.fetch("tools")).not_to have_key("stale_tool")
      expect(persisted.fetch("archived_tools")).to have_key("stale_tool")
      expect(persisted.dig("archived_tools", "stale_tool", "archived_at")).not_to be_nil
    end
  end
end
