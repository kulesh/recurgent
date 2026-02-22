# frozen_string_literal: true

require "fileutils"
require "json"

class Agent
  # Agent::SimulationRunLedger persists simulation-run evidence records.
  class SimulationRunLedger
    def initialize(path:)
      @path = path.to_s
    end

    def append(entry)
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, "a") { |file| file.puts(JSON.generate(entry)) }
      entry
    end

    def entries
      return [] unless File.exist?(path)

      File.readlines(path).filter_map do |line|
        next if line.to_s.strip.empty?

        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end

    private

    attr_reader :path
  end
end
