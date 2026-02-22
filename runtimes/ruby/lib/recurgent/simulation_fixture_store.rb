# frozen_string_literal: true

require "fileutils"
require "json"

class Agent
  # Agent::SimulationFixtureStore persists deterministic fixture/replay artifacts.
  class SimulationFixtureStore
    def initialize(root:)
      @root = root.to_s
    end

    def read(pack_id:, checksum:, seed:)
      path = _fixture_path(pack_id: pack_id, checksum: checksum, seed: seed)
      return nil unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end

    def write(pack_id:, checksum:, seed:, payload:)
      path = _fixture_path(pack_id: pack_id, checksum: checksum, seed: seed)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(payload))
      path
    end

    private

    attr_reader :root

    def _fixture_path(pack_id:, checksum:, seed:)
      File.join(root, pack_id.to_s, checksum.to_s, "seed-#{seed}.json")
    end
  end
end
