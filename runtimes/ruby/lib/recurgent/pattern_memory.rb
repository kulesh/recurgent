# frozen_string_literal: true

class Agent
  # Agent::PatternMemoryStore — bounded cross-session capability-pattern event memory,
  # pattern prompting, capability extraction, and user correction detection.
  module PatternMemoryStore
    # --- Memory Store ---

    PATTERN_MEMORY_SCHEMA_VERSION = 1
    PATTERN_MEMORY_RETENTION = 50

    # --- Pattern Prompting ---

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

    # --- Capability Extraction ---

    CAPABILITY_SIGNAL_MAP = {
      "rss_parse" => [
        ["require_rss", /require\s+["']rss["']/],
        ["rss_parser_constant", /\bRSS::Parser\b/]
      ],
      "xml_parse" => [
        ["require_rexml_document", %r{require\s+["']rexml/document["']}],
        ["rexml_document_constant", /\bREXML::Document\b/]
      ],
      "http_fetch" => [
        ["net_http_constant", /\bNet::HTTP\b/],
        ["web_fetcher_tool_call", /tool\(\s*["']web_fetcher["']\s*\)/],
        ["web_fetcher_delegate_call", /delegate\(\s*["']web_fetcher["']\s*[,)]/]
      ],
      "html_extract" => [
        ["nokogiri_html", /\bNokogiri::HTML\b/],
        ["html_anchor_scan", %r{scan\(\s*/.+<a\b.+/[mixounes]*\s*\)}m],
        ["html_heading_scan", %r{scan\(\s*/.+<h[1-6]\b.+/[mixounes]*\s*\)}m]
      ]
    }.freeze

    # --- User Correction Signals ---

    USER_CORRECTION_REASK_WINDOW_SECONDS = 180
    USER_CORRECTION_MIN_OVERLAP_RATIO = 0.67

    private

    # --- Memory Store ---

    def _record_pattern_memory_event(method_name:, state:, call_context:)
      return unless _record_pattern_memory_for_source?(state.program_source)

      timestamp = Time.now.utc
      user_correction = _detect_temporal_reask_user_correction(
        method_name: method_name,
        state: state,
        call_context: call_context,
        timestamp: timestamp
      )
      _capture_user_correction_state!(state, user_correction)
      _pattern_memory_append_event(
        role: @role,
        event: _build_pattern_memory_event(
          method_name: method_name,
          state: state,
          call_context: call_context,
          timestamp: timestamp,
          user_correction: user_correction
        )
      )
    rescue StandardError => e
      warn "[AGENT PATTERNS #{@role}.#{method_name}] failed to persist pattern memory: #{e.class}: #{e.message}" if @debug
    end

    def _build_pattern_memory_event(method_name:, state:, call_context:, timestamp:, user_correction:)
      event = {
        "timestamp" => timestamp.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
        "recorded_at_ms" => (timestamp.to_f * 1000).to_i,
        "role" => @role,
        "method_name" => method_name.to_s,
        "trace_id" => call_context&.fetch(:trace_id, nil),
        "call_id" => call_context&.fetch(:call_id, nil),
        "parent_call_id" => call_context&.fetch(:parent_call_id, nil),
        "depth" => call_context&.fetch(:depth, nil),
        "had_delegated_calls" => call_context&.fetch(:had_child_calls, false) == true,
        "capability_patterns" => Array(state.capability_patterns).map(&:to_s).uniq,
        "outcome_status" => state.outcome&.status,
        "error_type" => state.outcome&.error_type
      }
      event["user_correction"] = user_correction if user_correction&.fetch("detected", false)
      event
    end

    def _record_pattern_memory_for_source?(program_source)
      %w[generated repaired].include?(program_source.to_s)
    end

    def _pattern_memory_recent_events(role:, method_name:, window:)
      store = _pattern_memory_load
      role_bucket = store.fetch("roles", {}).fetch(role.to_s, {})
      events = Array(role_bucket["events"])
      events.select! { |event| event["method_name"].to_s == method_name.to_s }
      events.last(window)
    end

    def _pattern_memory_append_event(role:, event:)
      store = _pattern_memory_load
      roles = store["roles"] ||= {}
      role_bucket = roles[role.to_s] ||= { "events" => [] }
      events = Array(role_bucket["events"])
      events << event
      role_bucket["events"] = events.last(PATTERN_MEMORY_RETENTION)
      _pattern_memory_write(store)
    end

    def _pattern_memory_load
      path = _toolstore_patterns_path
      return _pattern_memory_template unless File.exist?(path)

      parsed = JSON.parse(File.read(path))
      return _pattern_memory_template unless _pattern_memory_schema_supported?(parsed["schema_version"])

      _pattern_memory_normalize(parsed)
    rescue JSON::ParserError => e
      _pattern_memory_quarantine_corrupt_file!(path, e)
      _pattern_memory_template
    rescue StandardError => e
      warn "[AGENT PATTERNS #{@role}] failed to load pattern store: #{e.class}: #{e.message}" if @debug
      _pattern_memory_template
    end

    def _pattern_memory_write(store)
      path = _toolstore_patterns_path
      FileUtils.mkdir_p(File.dirname(path))
      payload = {
        "schema_version" => PATTERN_MEMORY_SCHEMA_VERSION,
        "roles" => _json_safe(store.fetch("roles", {}))
      }

      temp_path = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.write(temp_path, JSON.generate(payload))
      File.rename(temp_path, path)
    ensure
      File.delete(temp_path) if defined?(temp_path) && temp_path && File.exist?(temp_path)
    end

    def _pattern_memory_template
      {
        "schema_version" => PATTERN_MEMORY_SCHEMA_VERSION,
        "roles" => {}
      }
    end

    def _pattern_memory_schema_supported?(schema_version)
      return true if schema_version.nil?
      return true if schema_version.to_i == PATTERN_MEMORY_SCHEMA_VERSION

      warn "[AGENT PATTERNS #{@role}] ignored pattern store schema=#{schema_version}" if @debug
      false
    end

    def _pattern_memory_normalize(parsed)
      raw_roles = parsed.fetch("roles", {})
      normalized_roles = {}
      return { "schema_version" => PATTERN_MEMORY_SCHEMA_VERSION, "roles" => normalized_roles } unless raw_roles.is_a?(Hash)

      raw_roles.each do |role, role_bucket|
        next unless role_bucket.is_a?(Hash)

        normalized_roles[role.to_s] = {
          "events" => Array(role_bucket["events"]).map { |event| _pattern_memory_normalize_event(event) }.compact
        }
      end

      {
        "schema_version" => PATTERN_MEMORY_SCHEMA_VERSION,
        "roles" => normalized_roles
      }
    end

    def _pattern_memory_normalize_event(event)
      return nil unless event.is_a?(Hash)

      _pattern_memory_normalize_event_base(event)
        .merge(_pattern_memory_normalize_event_trace(event))
        .merge(_pattern_memory_normalize_event_outcome(event))
    end

    def _pattern_memory_normalize_event_base(event)
      {
        "timestamp" => event["timestamp"].to_s,
        "recorded_at_ms" => event["recorded_at_ms"].to_i,
        "role" => event["role"].to_s,
        "method_name" => event["method_name"].to_s,
        "capability_patterns" => Array(event["capability_patterns"]).map(&:to_s).uniq
      }
    end

    def _pattern_memory_normalize_event_trace(event)
      {
        "trace_id" => event["trace_id"]&.to_s,
        "call_id" => event["call_id"]&.to_s,
        "parent_call_id" => event["parent_call_id"]&.to_s,
        "depth" => event["depth"],
        "had_delegated_calls" => event["had_delegated_calls"] == true
      }
    end

    def _pattern_memory_normalize_event_outcome(event)
      {
        "outcome_status" => event["outcome_status"],
        "error_type" => event["error_type"],
        "user_correction" => _pattern_memory_normalize_user_correction(event["user_correction"])
      }
    end

    def _pattern_memory_quarantine_corrupt_file!(path, error)
      return unless File.exist?(path)

      quarantined_path = "#{path}.corrupt-#{Time.now.utc.strftime("%Y%m%dT%H%M%S")}"
      FileUtils.mv(path, quarantined_path)
      return unless @debug

      warn "[AGENT PATTERNS #{@role}] quarantined corrupt pattern store: #{File.basename(quarantined_path)} (#{error.class})"
    rescue StandardError => e
      warn "[AGENT PATTERNS #{@role}] failed to quarantine corrupt pattern store: #{e.message}" if @debug
    end

    # --- Pattern Prompting ---

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

    # --- Capability Extraction ---

    def _extract_capability_patterns(method_name:, role:, code:, args:, kwargs:, outcome:, program_source:)
      _ = [method_name, role, args, kwargs, outcome, program_source]
      source = code.to_s
      return { patterns: [], evidence: {} } if source.strip.empty?

      patterns, evidence = _extract_signal_based_patterns(source)
      _append_news_headline_pattern!(patterns, evidence, source)
      { patterns: patterns.uniq, evidence: evidence }
    end

    def _extract_signal_based_patterns(source)
      patterns = []
      evidence = {}

      CAPABILITY_SIGNAL_MAP.each do |label, signal_checks|
        matches = signal_checks.filter_map do |signal_name, matcher|
          signal_name if source.match?(matcher)
        end
        next if matches.empty?

        patterns << label
        evidence[label] = matches
      end

      [patterns, evidence]
    end

    def _append_news_headline_pattern!(patterns, evidence, source)
      return unless _news_headline_extract_pattern?(source)

      patterns << "news_headline_extract"
      evidence["news_headline_extract"] = ["iterates_collection_and_extracts_title_and_link"]
    end

    def _news_headline_extract_pattern?(source)
      has_iteration = source.match?(
        /\.map\s+do|\.map\s*\{|\.each\s+do|\.each\s*\{|\.each_with_object\s*\(|\.collect\s+do|\.collect\s*\{|\bfor\s+\w+\s+in\b/
      )
      has_title = source.match?(/title\s*:|["']title["']\s*=>|\[:title\]|\["title"\]|\.title\b/)
      has_link = source.match?(/link\s*:|["']link["']\s*=>|\[:link\]|\["link"\]|\.link\b/)
      has_iteration && has_title && has_link
    end

    # --- User Correction Signals ---

    def _capture_user_correction_state!(state, user_correction)
      detected = user_correction.is_a?(Hash) && user_correction["detected"] == true
      state.user_correction_detected = detected
      state.user_correction_signal = detected ? user_correction["signal"] : nil
      state.user_correction_reference_call_id = detected ? user_correction["correction_of_call_id"] : nil
    end

    def _detect_temporal_reask_user_correction(method_name:, state:, call_context:, timestamp:)
      return nil unless _eligible_reask_user_correction_call?(method_name: method_name, call_context: call_context)

      previous_event = _latest_pattern_memory_event(role: @role, method_name: method_name)
      return nil unless _temporal_reask_match?(previous_event, call_context: call_context, timestamp: timestamp)

      previous_patterns = _normalized_capability_patterns(previous_event["capability_patterns"])
      current_patterns = _normalized_capability_patterns(state.capability_patterns)
      if _near_identical_capability_patterns?(previous_patterns, current_patterns)
        return _temporal_reask_with_pattern_overlap(previous_event, previous_patterns, current_patterns)
      end

      return _temporal_reask_without_tooling(previous_event) if _no_tooling_reask?(previous_event, current_patterns, call_context)

      nil
    end

    def _temporal_reask_with_pattern_overlap(previous_event, previous_patterns, current_patterns)
      {
        "detected" => true,
        "signal" => "temporal_reask",
        "correction_of_call_id" => previous_event["call_id"].to_s,
        "matched_capability_patterns" => (current_patterns & previous_patterns)
      }
    end

    def _temporal_reask_without_tooling(previous_event)
      {
        "detected" => true,
        "signal" => "temporal_reask_no_tooling",
        "correction_of_call_id" => previous_event["call_id"].to_s,
        "matched_capability_patterns" => []
      }
    end

    def _eligible_reask_user_correction_call?(method_name:, call_context:)
      return false unless call_context.is_a?(Hash)
      return false unless call_context.fetch(:depth, nil).to_i.zero?
      return false if call_context.fetch(:trace_id, nil).to_s.empty?
      return false if method_name.to_s.strip.empty?

      true
    end

    def _latest_pattern_memory_event(role:, method_name:)
      _pattern_memory_recent_events(role: role, method_name: method_name, window: 1).last
    end

    def _temporal_reask_match?(previous_event, call_context:, timestamp:)
      return false unless previous_event.is_a?(Hash)
      return false unless previous_event.fetch("depth", nil).to_i.zero?
      return false unless previous_event.fetch("trace_id", nil).to_s == call_context.fetch(:trace_id, nil).to_s

      previous_recorded_at_ms = previous_event["recorded_at_ms"].to_i
      return false unless previous_recorded_at_ms.positive?

      elapsed_seconds = ((timestamp.to_f * 1000).to_i - previous_recorded_at_ms).to_f / 1000
      elapsed_seconds.between?(0, USER_CORRECTION_REASK_WINDOW_SECONDS)
    end

    def _near_identical_capability_patterns?(left_patterns, right_patterns)
      overlap = (left_patterns & right_patterns).length
      return false if overlap.zero?

      max_size = [left_patterns.length, right_patterns.length].max
      return false unless max_size.positive?

      (overlap.to_f / max_size) >= USER_CORRECTION_MIN_OVERLAP_RATIO
    end

    def _no_tooling_reask?(previous_event, current_patterns, call_context)
      previous_patterns = _normalized_capability_patterns(previous_event["capability_patterns"])
      return false unless previous_patterns.empty? && current_patterns.empty?
      return false if previous_event.fetch("had_delegated_calls", false) == true
      return false if call_context.fetch(:had_child_calls, false) == true

      true
    end

    def _normalized_capability_patterns(patterns)
      Array(patterns).map(&:to_s).reject(&:empty?).uniq.sort
    end

    def _pattern_memory_normalize_user_correction(value)
      return nil unless value.is_a?(Hash)
      return nil unless value["detected"] == true

      {
        "detected" => true,
        "signal" => value["signal"].to_s,
        "correction_of_call_id" => value["correction_of_call_id"]&.to_s,
        "matched_capability_patterns" => Array(value["matched_capability_patterns"]).map(&:to_s).uniq.sort
      }
    end
  end
end
