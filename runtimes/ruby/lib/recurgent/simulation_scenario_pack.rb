# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

class Agent
  # Agent::SimulationScenarioPack loads and validates scenario packs from YAML.
  class SimulationScenarioPack
    attr_reader :path

    def self.load(path)
      new(path).load
    end

    def initialize(path)
      @path = path.to_s
    end

    def load
      raw = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
      normalized = Agent::SimulationPackContract.validate!(raw, source_path: path)
      normalized.merge("checksum_sha256" => _checksum_for(normalized))
    end

    private

    def _checksum_for(normalized_pack)
      Digest::SHA256.hexdigest(JSON.generate(normalized_pack))
    end
  end
end
