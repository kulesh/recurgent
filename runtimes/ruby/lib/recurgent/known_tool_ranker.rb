# frozen_string_literal: true

require "time"

class Agent
  # Agent::KnownToolRanker — ranking strategy for bounded known-tool prompt injection.
  module KnownToolRanker
    private

    def _rank_known_tools_for_prompt(tools)
      tools.sort_by do |name, metadata|
        score = _known_tool_utility_score(metadata)
        usage = _known_tool_usage_count(metadata)
        [-score, -usage, name.to_s]
      end
    end

    def _known_tool_utility_score(metadata)
      success_rate = _known_tool_success_rate(metadata)
      recency_decay = _known_tool_recency_decay(metadata)
      usage_bonus = Math.log(1 + _known_tool_usage_count(metadata)) / 10.0
      (success_rate * recency_decay) + usage_bonus
    end

    def _known_tool_success_rate(metadata)
      success_count = _known_tool_metric(metadata, :success_count)
      failure_count = _known_tool_metric(metadata, :failure_count)
      total = success_count + failure_count
      return 0.5 if total.zero?

      success_count.to_f / total
    end

    def _known_tool_usage_count(metadata)
      _known_tool_metric(metadata, :usage_count)
    end

    def _known_tool_metric(metadata, key)
      return 0 unless metadata.is_a?(Hash)

      value = metadata[key] || metadata[key.to_s]
      value.to_i
    end

    def _known_tool_recency_decay(metadata)
      last_used_raw = metadata.is_a?(Hash) ? (metadata[:last_used_at] || metadata["last_used_at"]) : nil
      return 0.25 if last_used_raw.nil? || last_used_raw.to_s.strip.empty?

      last_used = Time.parse(last_used_raw.to_s).utc
      days_since = [(Time.now.utc - last_used) / 86_400.0, 0.0].max
      Math.exp(-days_since / 30.0)
    rescue ArgumentError
      0.25
    end
  end
end
