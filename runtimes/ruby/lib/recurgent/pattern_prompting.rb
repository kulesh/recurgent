# frozen_string_literal: true

class Agent
  # Agent::PatternPrompting — summarize recent capability patterns for depth-0 dynamic prompts.
  module PatternPrompting
    PATTERN_MEMORY_PROMPT_WINDOW = 5
    PATTERN_MEMORY_PROMPT_LIMIT = 4
    PATTERN_MEMORY_PROMPT_MIN_REPEAT = 2
    CAPABILITY_TOOL_SIGNALS = {
      "http_fetch" => %w[http fetch web url request],
      "rss_parse" => %w[rss feed parse parser xml],
      "xml_parse" => %w[xml parse parser],
      "html_extract" => %w[html extract scrape scraper parse],
      "news_headline_extract" => %w[headline news title link feed rss]
    }.freeze

    private

    def _recent_patterns_prompt(method_name:, depth:)
      return "" unless depth.to_i.zero?
      return "" unless _dynamic_dispatch_method?(method_name)

      summaries = _recent_pattern_summaries(role: @role, method_name: method_name)
      return "" if summaries.empty?

      lines = summaries.map do |summary|
        tool_presence = _tool_presence_for_capability(summary[:capability])
        "- #{summary[:capability]}: seen #{summary[:count]} of last #{summary[:window]} #{method_name} calls, tool_present=#{tool_presence}"
      end

      <<~PROMPT
        <recent_patterns>
        #{lines.join("\n")}
        </recent_patterns>

        <promotion_nudge>
        - If a general capability repeats and no Tool exists, consider Forging now.
        </promotion_nudge>
      PROMPT
    end

    def _recent_pattern_summaries(role:, method_name:)
      events = _pattern_memory_recent_events(role: role, method_name: method_name, window: PATTERN_MEMORY_PROMPT_WINDOW)
      return [] if events.empty?

      aggregates = _pattern_memory_aggregates(events)
      entries = _pattern_prompt_entries(aggregates, window: events.length)
      _rank_pattern_entries(entries).first(PATTERN_MEMORY_PROMPT_LIMIT)
    end

    def _pattern_memory_aggregates(events)
      aggregates = Hash.new { |hash, key| hash[key] = { count: 0, last_seen_at: "" } }

      events.each do |event|
        timestamp = event["timestamp"].to_s
        Array(event["capability_patterns"]).map(&:to_s).uniq.each do |capability|
          aggregates[capability][:count] += 1
          aggregates[capability][:last_seen_at] = timestamp
        end
      end

      aggregates
    end

    def _pattern_prompt_entries(aggregates, window:)
      aggregates.filter_map do |capability, aggregate|
        next if aggregate[:count] < PATTERN_MEMORY_PROMPT_MIN_REPEAT

        {
          capability: capability,
          count: aggregate[:count],
          last_seen_at: aggregate[:last_seen_at],
          window: window
        }
      end
    end

    def _rank_pattern_entries(entries)
      entries.sort do |left, right|
        by_count = right[:count] <=> left[:count]
        next by_count unless by_count.zero?

        by_recency = right[:last_seen_at].to_s <=> left[:last_seen_at].to_s
        next by_recency unless by_recency.zero?

        left[:capability] <=> right[:capability]
      end
    end

    def _tool_presence_for_capability(capability)
      tool_name = _known_tool_for_capability(capability)
      tool_name.nil? ? "false" : "true(#{tool_name})"
    end

    def _known_tool_for_capability(capability)
      tools = @context[:tools]
      signals = _tool_signals_for_capability(capability)
      return nil unless tools.is_a?(Hash) && signals

      best_name, best_score = _ranked_tool_candidates(tools, signals).max_by { |name, score| [score, name] }
      best_score.to_i.positive? ? best_name : nil
    end

    def _tool_signals_for_capability(capability)
      CAPABILITY_TOOL_SIGNALS[capability.to_s]
    end

    def _ranked_tool_candidates(tools, signals)
      tools.keys.map(&:to_s).map do |tool_name|
        searchable = _tool_searchable_text(tool_name, tools)
        [tool_name, signals.count { |signal| searchable.include?(signal) }]
      end
    end

    def _tool_searchable_text(tool_name, tools)
      metadata = tools[tool_name] || tools[tool_name.to_sym]
      "#{tool_name} #{_extract_tool_purpose(metadata)}".downcase
    end
  end
end
