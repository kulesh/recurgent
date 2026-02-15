# frozen_string_literal: true

class Agent
  # Agent::CapabilityPatternExtractor — deterministic capability tagging from generated Ruby code.
  module CapabilityPatternExtractor
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

    private

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
  end
end
