# frozen_string_literal: true

require "spec_helper"

RSpec.describe Agent::DependencyManifest do
  describe ".normalize!" do
    it "returns an empty frozen manifest for nil dependencies" do
      manifest = described_class.normalize!(nil)

      expect(manifest).to eq([])
      expect(manifest).to be_frozen
    end

    it "normalizes names, default versions, and sort order" do
      manifest = described_class.normalize!(
        [
          { name: "Nokogiri", version: "~> 1.16" },
          { name: "httparty" }
        ]
      )

      expect(manifest).to eq(
        [
          { name: "httparty", version: ">= 0" },
          { name: "nokogiri", version: "~> 1.16" }
        ]
      )
      expect(manifest).to be_frozen
      expect(manifest.first).to be_frozen
    end

    it "deduplicates identical declarations" do
      manifest = described_class.normalize!(
        [
          { name: "nokogiri", version: "~> 1.16" },
          { name: "NOKOGIRI", version: "~> 1.16" }
        ]
      )

      expect(manifest).to eq([{ name: "nokogiri", version: "~> 1.16" }])
    end

    it "raises for non-array dependencies" do
      expect do
        described_class.normalize!("nokogiri")
      end.to raise_error(Agent::InvalidDependencyManifestError, /dependencies must be an Array/)
    end

    it "raises for non-object entries" do
      expect do
        described_class.normalize!(["nokogiri"])
      end.to raise_error(Agent::InvalidDependencyManifestError, /dependencies\[0\] must be an object/)
    end

    it "raises for invalid gem names" do
      expect do
        described_class.normalize!([{ name: "nokogiri!" }])
      end.to raise_error(Agent::InvalidDependencyManifestError, /name is invalid/)
    end

    it "raises for blank versions when provided" do
      expect do
        described_class.normalize!([{ name: "nokogiri", version: " " }])
      end.to raise_error(Agent::InvalidDependencyManifestError, /version must be a non-empty String/)
    end

    it "raises for conflicting duplicate declarations" do
      expect do
        described_class.normalize!(
          [
            { name: "nokogiri", version: "~> 1.16" },
            { name: "Nokogiri", version: "~> 1.17" }
          ]
        )
      end.to raise_error(Agent::InvalidDependencyManifestError, /conflicts with prior declaration/)
    end
  end
end
