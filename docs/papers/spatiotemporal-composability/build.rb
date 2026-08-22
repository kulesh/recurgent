# frozen_string_literal: true

# Builds index.html for the spatiotemporal-composability guide.
#
#   ruby build.rb
#
# Assembly steps:
#   1. Inject the reproduced paper fragments (paper/*.html) into the template.
#   2. Segment cordis.rb, cordis_calculus.rb, and cordis_loader.rb by class,
#      syntax-highlight them, and turn every paper citation in comments and
#      strings into a trace link.
#   3. Extract excerpts from the check suites; embed the demos whole.
#   4. Run both check suites and both demos; embed their real output.
#   5. Replace the paper's diagram placeholders with hand-drawn SVG figures.
#   6. Inject "In the Ruby" backlink rows under every cited paper block.
#   7. Verify every internal link resolves; refuse to write the page otherwise.

require "cgi"
require "English"
require "strscan"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

DIR = __dir__

# --- anchors present in the reproduced paper ----------------------------------

DEFS  = [1, 2, 3, 6, 8, 9, 12, 17, 19, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 36, 37, 39,
         41, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 58, 60, 65, 67, 69, 74].freeze
THMS  = [4, 5, 7, 10, 11, 13, 14, 15, 16, 20, 40, 42, 59, 61, 63, 64, 66, 73].freeze
LEMMAS = [18, 35, 38, 54, 55, 56, 57, 68, 70, 71, 72].freeze
CORS = [21, 62].freeze
SECTIONS = %w[
  s1 s1-1 s1-2 s1-2-1 s1-2-2 s1-2-3 s1-3
  s2 s2-1 s2-2 s2-3
  s3 s3-1 s3-1-1 s3-1-2 s3-1-3 s3-2 s3-2-1 s3-2-2 s3-2-3
  s3-3 s3-3-1 s3-3-2 s3-3-3
  s4 s4-1 s4-2 s4-3 s4-3-1 s4-3-2 s4-3-3 s4-3-4 s4-4 s4-4-1 s4-4-2 s4-4-3 s4-4-4 s4-4-5
  s5 s5-1 s5-1-1 s5-1-2 s5-1-3 s5-1-4 s5-2 s5-2-1 s5-2-2 s5-3
  s6 s6-1 s6-2 s6-3 s6-4 s6-5 s6-6 s6-7
  s7 s7-1 s7-2 s7-3 s7-4 s8 refs
].freeze
EQS = (1..65).to_a.freeze
ALGS = (1..10).to_a.freeze
RULES = %w[
  rule-o-insert rule-o-retire rule-o-remove rule-l-reload rule-l-unload-base
  rule-l-begin rule-l-iter rule-l-finish rule-l-divert rule-l-raise rule-l-leave rule-l-unload
].freeze

TEMPORAL = SECTIONS.select { |s| s.start_with?("s3-1") } + ["s3"] +
           DEFS.select { |n| n < 22 }.map { |n| "d#{n}" } +
           THMS.select { |n| n <= 20 }.map { |n| "t#{n}" } + %w[l18 c21] + (4..19).map { |n| "eq#{n}" }
SPATIAL = SECTIONS.select { |s| s.start_with?("s3-2") } +
          DEFS.grep(22..31).map { |n| "d#{n}" } + (20..30).map { |n| "eq#{n}" }
NEUTRAL = SECTIONS.select { |s| s.start_with?("s1", "s2", "s6", "s7", "s8", "refs") } + (1..3).map { |n| "eq#{n}" }

# Everything §3.3–§5 — where the two dimensions meet — carries the third hue.
def hue_class(anchor)
  return "tr-t" if TEMPORAL.include?(anchor)
  return "tr-s" if SPATIAL.include?(anchor)
  return "tr-n" if NEUTRAL.include?(anchor)

  "tr-u"
end

# rubocop:disable Metrics/CyclomaticComplexity -- one arm per anchor family
def anchor_exists?(anchor)
  case anchor
  when /\Ad(\d+)\z/ then DEFS.include?(Regexp.last_match(1).to_i)
  when /\At(\d+)\z/ then THMS.include?(Regexp.last_match(1).to_i)
  when /\Al(\d+)\z/ then LEMMAS.include?(Regexp.last_match(1).to_i)
  when /\Ac(\d+)\z/ then CORS.include?(Regexp.last_match(1).to_i)
  when /\Aeq(\d+)\z/ then EQS.include?(Regexp.last_match(1).to_i)
  when /\Aalg(\d+)\z/ then ALGS.include?(Regexp.last_match(1).to_i)
  when /\A(?:tbl|fig)[12]\z/ then true
  when /\Arule-/ then RULES.include?(anchor)
  else SECTIONS.include?(anchor)
  end
end
# rubocop:enable Metrics/CyclomaticComplexity

def trace_link(anchor, text)
  target = anchor_exists?(anchor) ? anchor : "beyond"
  %(<a class="trace #{hue_class(target)}" href="##{target}">#{text}</a>)
end

# Turn paper citations inside an HTML-escaped string into trace links.
KIND_PREFIX = { "Definition" => "d", "Theorem" => "t", "Lemma" => "l", "Corollary" => "c" }.freeze

def linkify(escaped)
  out = escaped.gsub(
    %r{(Definitions?|Theorems?|Lemmas?|Corollar(?:y|ies))([-\s]|&nbsp;)(\d+)((?:\.\d+)?)((?:\s*(?:,|&amp;|/|–|—|and)\s*\d+)*)}
  ) do
    kind, sep, num, clause, rest = Regexp.last_match[1..5]
    prefix = KIND_PREFIX[kind.sub(/s\z|ies\z/) { |m| m == "ies" ? "y" : "" }]
    linked_rest = rest.gsub(/\d+/) { |n| trace_link("#{prefix}#{n}", n) }
    "#{kind}#{sep}#{trace_link("#{prefix}#{num}", "#{num}#{clause}")}#{linked_rest}"
  end
  out = out.gsub(/eq\.\s*(\d+)/) { trace_link("eq#{Regexp.last_match(1)}", Regexp.last_match(0)) }
  out.gsub(/§(\d+(?:\.\d+)*)/) do
    trace_link("s#{Regexp.last_match(1).tr(".", "-")}", Regexp.last_match(0))
  end
end

# --- Ruby syntax highlighting -------------------------------------------------

KEYWORDS = /\b(?:def|end|class|module|do|if|elsif|else|unless|while|until|return|self|nil|true|false|
  yield|alias|then|case|when|next|break|rescue|raise|begin|ensure|and|or|not|in|
  require_relative|require|attr_reader|include|module_function|private)\b/x

def esc(text)
  CGI.escapeHTML(text)
end

# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Lint/DuplicateBranch
def highlight_line(line)
  s = StringScanner.new(line.chomp)
  out = +""
  until s.eos?
    out << if (tok = s.scan(/"(?:\\.|[^"\\])*"/))
             %(<span class="s">#{linkify(esc(tok))}</span>)
           elsif (tok = s.scan(/#.*/))
             %(<span class="c">#{linkify(esc(tok))}</span>)
           elsif (tok = s.scan("::"))
             esc(tok)
           elsif (tok = s.scan(/:\w+[?!]?/))
             %(<span class="y">#{esc(tok)}</span>)
           elsif (tok = s.scan(KEYWORDS))
             %(<span class="k">#{esc(tok)}</span>)
           elsif (tok = s.scan(/[A-Z]\w*/))
             %(<span class="C">#{esc(tok)}</span>)
           elsif (tok = s.scan(/\d[\d_]*(?:\.\d+)?/))
             %(<span class="n">#{esc(tok)}</span>)
           elsif (tok = s.scan(/\w+[?!]?/))
             esc(tok)
           else
             esc(s.getch)
           end
  end
  out
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Lint/DuplicateBranch

def render_code(lines, first_line_number, source_label)
  body = lines.each_with_index.map do |line, i|
    %(<span class="no">#{first_line_number + i}</span>#{highlight_line(line)})
  end.join("\n")
  last = first_line_number + lines.length - 1
  <<~HTML
    <p class="code-meta">#{source_label} · lines #{first_line_number}–#{last}</p>
    <div class="codewrap"><pre class="code"><code>#{body}</code></pre></div>
  HTML
end

# --- segment cordis.rb by class/module ----------------------------------------

CORDIS_SEGMENTS = %w[
  Effect EffectContext Independence Satisfaction CoeffectContext
  Coeffects Coeffect InterceptedContext IsolatedContext Component ActivationScope System
].freeze

# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
def cordis_segments
  lines = File.readlines(File.join(DIR, "cordis.rb"))
  decls = {}
  lines.each_with_index do |line, i|
    next unless line =~ /\A  (?:class|module) (\w+)/

    name = Regexp.last_match(1)
    decls[name] = i if CORDIS_SEGMENTS.include?(name) && !decls.key?(name)
  end
  missing = CORDIS_SEGMENTS - decls.keys
  abort "build: could not find #{missing.join(", ")} in cordis.rb" unless missing.empty?

  starts = decls.transform_values do |i|
    start = i
    start -= 1 while start.positive? && lines[start - 1] =~ /\A  #/
    start
  end
  ordered = starts.sort_by { |_, v| v }
  final_end = lines.rindex { |l| l.chomp == "end" }

  segments = { "Prelude" => (0...ordered.first[1]) }
  ordered.each_with_index do |(name, start), idx|
    stop = idx + 1 < ordered.length ? ordered[idx + 1][1] : final_end
    segments[name] = (start...stop)
  end
  segments.transform_values do |range|
    seg = lines[range]
    seg.pop while seg.last && seg.last.strip.empty?
    [seg, range.first + 1]
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

# Segment cordis_calculus.rb by its 4-space-indented class declarations; the
# prelude (the modeling-choices header) is a segment of its own.
# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
def calculus_segments
  lines = File.readlines(File.join(DIR, "cordis_calculus.rb"))
  decls = {}
  lines.each_with_index do |line, i|
    next unless line =~ /\A    class (\w+)/

    name = Regexp.last_match(1)
    decls[name] = i if %w[Component Fiber Machine].include?(name) && !decls.key?(name)
  end
  starts = decls.transform_values do |i|
    start = i
    start -= 1 while start.positive? && lines[start - 1] =~ /\A    #/
    start
  end
  ordered = starts.sort_by { |_, v| v }
  final_end = lines.length - 2 # keep Machine's own end; drop the two closing module ends
  segments = { "CalcPrelude" => (0...ordered.first[1]) }
  ordered.each_with_index do |(name, start), idx|
    stop = idx + 1 < ordered.length ? ordered[idx + 1][1] : final_end
    segments["Calc#{name}"] = (start...stop)
  end
  segments.transform_values do |range|
    seg = lines[range]
    seg.pop while seg.last && seg.last.strip.empty?
    [seg, range.first + 1]
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

# --- excerpts -----------------------------------------------------------------

def extract(lines, from_re, to_re, inclusive: true)
  from = lines.index { |l| l =~ from_re } or abort "build: excerpt start #{from_re} not found"
  to = (from...lines.length).find { |i| lines[i] =~ to_re } or abort "build: excerpt end #{to_re} not found"
  to -= 1 unless inclusive
  seg = lines[from..to]
  seg.pop while seg.last && seg.last.strip.empty?
  [seg, from + 1]
end

# --- run the scripts ----------------------------------------------------------

def capture(script)
  out = `cd #{DIR} && ruby #{script} 2>&1`
  abort "build: #{script} failed:\n#{out}" unless $CHILD_STATUS.success?
  out
end

def render_terminal(script, output)
  lines = output.lines.map do |line|
    rendered = linkify(esc(line.chomp))
    rendered = %(<span class="pass">#{rendered}</span>) if line.lstrip.start_with?("✓", "All checks passed")
    rendered
  end
  <<~HTML
    <div class="codewrap"><pre class="term"><span class="prompt">$ ruby #{script}</span>
    #{lines.join("\n")}</pre></div>
  HTML
end

# --- the redrawn paper figures ------------------------------------------------

FIG_STYLE = 'style="color: var(--ink); font-family: var(--sans);"'

FIG_SQUARE = <<~SVG.freeze
  <figure class="pfig">
    <div class="figwrap">
    <svg viewBox="0 0 420 216" role="img" aria-label="Commutative square: f maps Gamma to Gamma along the top, f prime equals track of f and g maps the effect context along the bottom, and pr1 projects each effect context up to Gamma." #{FIG_STYLE}>
      <defs><marker id="fsq-a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse"><path d="M 0 1 L 9 5 L 0 9 z" fill="currentColor"></path></marker></defs>
      <text x="70" y="56" text-anchor="middle" font-size="15" font-style="italic" fill="currentColor">Γ</text>
      <text x="350" y="56" text-anchor="middle" font-size="15" font-style="italic" fill="currentColor">Γ</text>
      <line x1="92" y1="51" x2="326" y2="51" stroke="currentColor" stroke-width="1.3" marker-end="url(#fsq-a)"></line>
      <text x="209" y="41" text-anchor="middle" font-size="12.5" font-style="italic" fill="currentColor">f</text>
      <text x="70" y="176" text-anchor="middle" font-size="15" fill="currentColor">∂<tspan font-style="italic">Γ</tspan></text>
      <text x="350" y="176" text-anchor="middle" font-size="15" fill="currentColor">∂<tspan font-style="italic">Γ</tspan></text>
      <line x1="92" y1="171" x2="326" y2="171" stroke="currentColor" stroke-width="1.3" marker-end="url(#fsq-a)"></line>
      <text x="209" y="192" text-anchor="middle" font-size="12.5" fill="currentColor"><tspan font-style="italic">f</tspan>′ = track(<tspan font-style="italic">f</tspan>, <tspan font-style="italic">g</tspan>)</text>
      <line x1="70" y1="156" x2="70" y2="70" stroke="currentColor" stroke-width="1.3" marker-end="url(#fsq-a)"></line>
      <text x="56" y="118" text-anchor="middle" font-size="11.5" fill="var(--muted)">pr₁</text>
      <line x1="350" y1="156" x2="350" y2="70" stroke="currentColor" stroke-width="1.3" marker-end="url(#fsq-a)"></line>
      <text x="366" y="118" text-anchor="middle" font-size="11.5" fill="var(--muted)">pr₁</text>
      <line x1="206" y1="66" x2="206" y2="150" stroke="var(--temporal)" stroke-width="1.2" marker-end="url(#fsq-a)"></line>
      <line x1="212" y1="66" x2="212" y2="150" stroke="var(--temporal)" stroke-width="1.2"></line>
      <text x="232" y="112" text-anchor="middle" font-size="11.5" fill="var(--temporal)">track</text>
    </svg>
    </div>
    <figcaption>Theorem 4's square: tracking is invisible one level down — pr₁ ∘ track(<i>f</i>, <i>g</i>) = <i>f</i> ∘ pr₁.</figcaption>
  </figure>
SVG

FIG_CHAIN = <<~SVG.freeze
  <figure class="pfig">
    <div class="figwrap">
    <svg viewBox="0 0 720 240" role="img" aria-label="A chain of tracked effects f1 through fn over Gamma, each lowered by track to the effect context, with a long recover arrow carrying the final effect context back to the initial one." #{FIG_STYLE}>
      <defs><marker id="fch-a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse"><path d="M 0 1 L 9 5 L 0 9 z" fill="currentColor"></path></marker>
      <marker id="fch-t" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse"><path d="M 0 1 L 9 5 L 0 9 z" fill="var(--temporal)"></path></marker></defs>
      <text x="90" y="56" text-anchor="middle" font-size="15" font-style="italic" fill="currentColor">Γ</text>
      <text x="250" y="56" text-anchor="middle" font-size="15" font-style="italic" fill="currentColor">Γ</text>
      <text x="410" y="56" text-anchor="middle" font-size="15" font-style="italic" fill="currentColor">Γ</text>
      <text x="570" y="56" text-anchor="middle" font-size="15" font-style="italic" fill="currentColor">Γ</text>
      <line x1="110" y1="51" x2="228" y2="51" stroke="currentColor" stroke-width="1.3" marker-end="url(#fch-a)"></line>
      <text x="169" y="40" text-anchor="middle" font-size="12" fill="currentColor"><tspan font-style="italic">f</tspan>₁</text>
      <line x1="270" y1="51" x2="388" y2="51" stroke="currentColor" stroke-width="1.1" stroke-dasharray="3 5"></line>
      <line x1="430" y1="51" x2="548" y2="51" stroke="currentColor" stroke-width="1.3" marker-end="url(#fch-a)"></line>
      <text x="489" y="40" text-anchor="middle" font-size="12" fill="currentColor"><tspan font-style="italic">f</tspan>ₙ</text>
      <text x="90" y="160" text-anchor="middle" font-size="15" fill="currentColor">∂<tspan font-style="italic">Γ</tspan></text>
      <text x="250" y="160" text-anchor="middle" font-size="15" fill="currentColor">∂<tspan font-style="italic">Γ</tspan></text>
      <text x="410" y="160" text-anchor="middle" font-size="15" fill="currentColor">∂<tspan font-style="italic">Γ</tspan></text>
      <text x="570" y="160" text-anchor="middle" font-size="15" fill="currentColor">∂<tspan font-style="italic">Γ</tspan></text>
      <line x1="110" y1="155" x2="228" y2="155" stroke="currentColor" stroke-width="1.3" marker-end="url(#fch-a)"></line>
      <text x="169" y="144" text-anchor="middle" font-size="12" fill="currentColor"><tspan font-style="italic">f</tspan>′₁</text>
      <line x1="270" y1="155" x2="388" y2="155" stroke="currentColor" stroke-width="1.1" stroke-dasharray="3 5"></line>
      <line x1="430" y1="155" x2="548" y2="155" stroke="currentColor" stroke-width="1.3" marker-end="url(#fch-a)"></line>
      <text x="489" y="144" text-anchor="middle" font-size="12" fill="currentColor"><tspan font-style="italic">f</tspan>′ₙ</text>
      <line x1="90" y1="68" x2="90" y2="138" stroke="var(--muted)" stroke-width="1.1" marker-end="url(#fch-a)"></line>
      <line x1="250" y1="68" x2="250" y2="138" stroke="var(--muted)" stroke-width="1.1" marker-end="url(#fch-a)"></line>
      <line x1="410" y1="68" x2="410" y2="138" stroke="var(--muted)" stroke-width="1.1" marker-end="url(#fch-a)"></line>
      <line x1="570" y1="68" x2="570" y2="138" stroke="var(--muted)" stroke-width="1.1" marker-end="url(#fch-a)"></line>
      <text x="70" y="107" text-anchor="middle" font-size="11" fill="var(--muted)">track</text>
      <path d="M 570 174 C 500 222, 160 222, 96 178" fill="none" stroke="var(--temporal)" stroke-width="1.4" marker-end="url(#fch-t)"></path>
      <text x="333" y="222" text-anchor="middle" font-size="12" fill="var(--temporal)">recover</text>
    </svg>
    </div>
    <figcaption>Tracked effects followed by recover carry the initial effect context back to itself (Definition 6, Theorem 7).</figcaption>
  </figure>
SVG

FIG_WITNESS = <<~SVG.freeze
  <figure class="pfig">
    <div class="figwrap">
    <svg viewBox="0 0 400 232" role="img" aria-label="Witness triangle: e sends Gamma down to the effect context, whose projections pr1 and pr2 recover the forward map f and inverse g running between the two copies of Gamma." #{FIG_STYLE}>
      <defs><marker id="fwt-a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse"><path d="M 0 1 L 9 5 L 0 9 z" fill="currentColor"></path></marker></defs>
      <text x="80" y="56" text-anchor="middle" font-size="15" font-style="italic" fill="currentColor">Γ</text>
      <text x="320" y="56" text-anchor="middle" font-size="15" font-style="italic" fill="currentColor">Γ</text>
      <line x1="100" y1="43" x2="296" y2="43" stroke="currentColor" stroke-width="1.3" marker-end="url(#fwt-a)"></line>
      <text x="198" y="33" text-anchor="middle" font-size="12.5" font-style="italic" fill="currentColor">f</text>
      <line x1="296" y1="61" x2="100" y2="61" stroke="var(--temporal)" stroke-width="1.3" stroke-dasharray="5 4" marker-end="url(#fwt-a)"></line>
      <text x="198" y="78" text-anchor="middle" font-size="12.5" font-style="italic" fill="var(--temporal)">g</text>
      <text x="200" y="204" text-anchor="middle" font-size="15" fill="currentColor">∂<tspan font-style="italic">Γ</tspan></text>
      <line x1="92" y1="72" x2="188" y2="186" stroke="currentColor" stroke-width="1.3" marker-end="url(#fwt-a)"></line>
      <text x="122" y="136" text-anchor="middle" font-size="12.5" font-style="italic" fill="currentColor">e</text>
      <line x1="212" y1="186" x2="310" y2="72" stroke="var(--muted)" stroke-width="1.1" marker-end="url(#fwt-a)"></line>
      <text x="280" y="136" text-anchor="middle" font-size="11.5" fill="var(--muted)">pr₁</text>
      <line x1="200" y1="182" x2="200" y2="96" stroke="var(--muted)" stroke-width="1.1" stroke-dasharray="3 4" marker-end="url(#fwt-a)"></line>
      <text x="219" y="128" text-anchor="middle" font-size="11.5" fill="var(--muted)">pr₂</text>
    </svg>
    </div>
    <figcaption>The witness condition of Definition 8: at each state, <i>e</i> yields a successor (pr₁) and an inverse (pr₂) with <i>g</i>(<i>δ</i>) = <i>γ</i> — the inverse verifiably reverses the transformation at the state where <i>e</i> was applied.</figcaption>
  </figure>
SVG

FIG_LIFT = <<~SVG.freeze
  <figure class="pfig">
    <div class="figwrap">
    <svg viewBox="0 0 640 336" role="img" aria-label="Two stacked witness triangles: e over Gamma with maps f and g, and e prime equals effect of e over the effect context with maps f prime and g prime, connected by the red effect arrow; pr1 projects each level onto the one above." #{FIG_STYLE}>
      <defs><marker id="flf-a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse"><path d="M 0 1 L 9 5 L 0 9 z" fill="currentColor"></path></marker>
      <marker id="flf-t" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 1 L 9 5 L 0 9 z" fill="var(--temporal)"></path></marker></defs>
      <text x="180" y="52" text-anchor="middle" font-size="15" font-style="italic" fill="currentColor">Γ</text>
      <text x="480" y="52" text-anchor="middle" font-size="15" font-style="italic" fill="currentColor">Γ</text>
      <line x1="200" y1="39" x2="456" y2="39" stroke="currentColor" stroke-width="1.3" marker-end="url(#flf-a)"></line>
      <text x="328" y="29" text-anchor="middle" font-size="12.5" font-style="italic" fill="currentColor">f</text>
      <line x1="456" y1="57" x2="200" y2="57" stroke="currentColor" stroke-width="1.1" stroke-dasharray="5 4" marker-end="url(#flf-a)"></line>
      <text x="328" y="74" text-anchor="middle" font-size="12.5" font-style="italic" fill="currentColor">g</text>
      <text x="180" y="180" text-anchor="middle" font-size="15" fill="currentColor">∂<tspan font-style="italic">Γ</tspan></text>
      <text x="480" y="180" text-anchor="middle" font-size="15" fill="currentColor">∂<tspan font-style="italic">Γ</tspan></text>
      <line x1="204" y1="167" x2="452" y2="167" stroke="currentColor" stroke-width="1.3" marker-end="url(#flf-a)"></line>
      <text x="328" y="157" text-anchor="middle" font-size="12.5" fill="currentColor"><tspan font-style="italic">f</tspan>′</text>
      <line x1="452" y1="185" x2="204" y2="185" stroke="currentColor" stroke-width="1.1" stroke-dasharray="5 4" marker-end="url(#flf-a)"></line>
      <text x="328" y="202" text-anchor="middle" font-size="12.5" fill="currentColor"><tspan font-style="italic">g</tspan>′</text>
      <text x="480" y="310" text-anchor="middle" font-size="15" fill="currentColor">∂²<tspan font-style="italic">Γ</tspan></text>
      <line x1="190" y1="68" x2="466" y2="164" stroke="currentColor" stroke-width="1.2" marker-end="url(#flf-a)"></line>
      <text x="310" y="122" text-anchor="middle" font-size="12.5" font-style="italic" fill="currentColor">e</text>
      <line x1="192" y1="196" x2="464" y2="294" stroke="currentColor" stroke-width="1.2" marker-end="url(#flf-a)"></line>
      <text x="310" y="252" text-anchor="middle" font-size="12.5" fill="currentColor"><tspan font-style="italic">e</tspan>′</text>
      <path d="M 120 78 C 92 118, 92 148, 120 188" fill="none" stroke="var(--temporal)" stroke-width="2" marker-end="url(#flf-t)"></path>
      <text x="66" y="138" text-anchor="middle" font-size="12.5" fill="var(--temporal)">effect</text>
      <line x1="496" y1="290" x2="496" y2="200" stroke="var(--muted)" stroke-width="1.1" marker-end="url(#flf-a)"></line>
      <text x="514" y="248" text-anchor="middle" font-size="11.5" fill="var(--muted)">pr₁</text>
      <line x1="496" y1="160" x2="496" y2="70" stroke="var(--muted)" stroke-width="1.1" marker-end="url(#flf-a)"></line>
      <text x="514" y="118" text-anchor="middle" font-size="11.5" fill="var(--muted)">pr₁</text>
    </svg>
    </div>
    <figcaption>The lift of Definition 12: undoing <i>e</i> is itself an effect one level up — <i>e</i>′ = effect(<i>e</i>) has forward map <i>g</i> composed onto the accumulator, and its own inverse is performing <i>e</i> again (Theorems 13–15).</figcaption>
  </figure>
SVG

FIG_LIFECYCLE1 = <<~SVG.freeze
  <figure class="pfig" id="fig1">
    <div class="figwrap">
    <svg viewBox="0 0 440 130" role="img" aria-label="Base component lifecycle: two states, Inactive and Active, with L-Reload from Inactive to Active and L-Unload back." #{FIG_STYLE}>
      <defs><marker id="flc1-a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse"><path d="M 0 1 L 9 5 L 0 9 z" fill="currentColor"></path></marker></defs>
      <rect x="30" y="45" width="120" height="40" rx="8" fill="var(--bg-sunken)" stroke="currentColor"></rect>
      <text x="90" y="70" text-anchor="middle" font-size="13" fill="currentColor">Inactive</text>
      <rect x="290" y="45" width="120" height="40" rx="8" fill="var(--bg-sunken)" stroke="currentColor"></rect>
      <text x="350" y="70" text-anchor="middle" font-size="13" fill="currentColor">Active</text>
      <line x1="152" y1="55" x2="286" y2="55" stroke="currentColor" stroke-width="1.3" marker-end="url(#flc1-a)"></line>
      <text x="220" y="45" text-anchor="middle" font-size="11.5" fill="var(--muted)">L-Reload</text>
      <line x1="286" y1="76" x2="152" y2="76" stroke="currentColor" stroke-width="1.3" marker-end="url(#flc1-a)"></line>
      <text x="220" y="96" text-anchor="middle" font-size="11.5" fill="var(--muted)">L-Unload</text>
    </svg>
    </div>
    <figcaption>Figure 1 — Base component lifecycle.</figcaption>
  </figure>
SVG

FIG_LIFECYCLE2 = <<~SVG.freeze
  <figure class="pfig" id="fig2">
    <div class="figwrap">
    <svg viewBox="0 0 660 320" role="img" aria-label="Lifecycle with transitions in progress: L-Begin from Inactive to Reloading; L-Iter loops on Reloading; L-Finish to Active; L-Divert and L-Raise from Reloading down to Unloading; L-Leave from Active to Unloading; L-Unload from Unloading back to Inactive. The two transition states are outlined." #{FIG_STYLE}>
      <defs><marker id="flc2-a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse"><path d="M 0 1 L 9 5 L 0 9 z" fill="currentColor"></path></marker></defs>
      <rect x="270" y="60" width="130" height="40" rx="8" fill="var(--temporal-soft)" stroke="var(--temporal)" stroke-width="1.6"></rect>
      <text x="335" y="85" text-anchor="middle" font-size="13" fill="var(--temporal)">Reloading</text>
      <rect x="40" y="150" width="120" height="40" rx="8" fill="var(--bg-sunken)" stroke="currentColor"></rect>
      <text x="100" y="175" text-anchor="middle" font-size="13" fill="currentColor">Inactive</text>
      <rect x="510" y="150" width="120" height="40" rx="8" fill="var(--bg-sunken)" stroke="currentColor"></rect>
      <text x="570" y="175" text-anchor="middle" font-size="13" fill="currentColor">Active</text>
      <rect x="270" y="240" width="130" height="40" rx="8" fill="var(--temporal-soft)" stroke="var(--temporal)" stroke-width="1.6"></rect>
      <text x="335" y="265" text-anchor="middle" font-size="13" fill="var(--temporal)">Unloading</text>
      <path d="M 300 56 C 310 22, 360 22, 370 56" fill="none" stroke="currentColor" stroke-width="1.2" marker-end="url(#flc2-a)"></path>
      <text x="335" y="24" text-anchor="middle" font-size="11.5" fill="var(--muted)">L-Iter</text>
      <line x1="130" y1="146" x2="272" y2="96" stroke="currentColor" stroke-width="1.2" marker-end="url(#flc2-a)"></line>
      <text x="168" y="106" text-anchor="middle" font-size="11.5" fill="var(--muted)">L-Begin</text>
      <line x1="398" y1="96" x2="540" y2="146" stroke="currentColor" stroke-width="1.2" marker-end="url(#flc2-a)"></line>
      <text x="502" y="106" text-anchor="middle" font-size="11.5" fill="var(--muted)">L-Finish</text>
      <line x1="335" y1="104" x2="335" y2="236" stroke="currentColor" stroke-width="1.2" marker-end="url(#flc2-a)"></line>
      <text x="378" y="160" text-anchor="middle" font-size="11.5" fill="var(--muted)">L-Divert</text>
      <text x="376" y="176" text-anchor="middle" font-size="11.5" fill="var(--muted)">L-Raise</text>
      <line x1="540" y1="194" x2="398" y2="246" stroke="currentColor" stroke-width="1.2" marker-end="url(#flc2-a)"></line>
      <text x="497" y="234" text-anchor="middle" font-size="11.5" fill="var(--muted)">L-Leave</text>
      <line x1="272" y1="246" x2="130" y2="194" stroke="currentColor" stroke-width="1.2" marker-end="url(#flc2-a)"></line>
      <text x="172" y="234" text-anchor="middle" font-size="11.5" fill="var(--muted)">L-Unload</text>
    </svg>
    </div>
    <figcaption>Figure 2 — Lifecycle with transitions in progress; the two transition states are outlined.</figcaption>
  </figure>
SVG

def replace_diagrams(html)
  html.gsub(%r{<p class="diagram-note"[^>]*>(.*?)</p>}m) do
    note = Regexp.last_match(1)
    case note
    when /Two stacked/ then FIG_LIFT
    when /chain of commutative/ then FIG_CHAIN
    when /commutative square/ then FIG_SQUARE
    when /A triangle in which/ then FIG_WITNESS
    when /\[Figure 1/ then FIG_LIFECYCLE1
    when /\[Figure 2/ then FIG_LIFECYCLE2
    else Regexp.last_match(0)
    end
  end
end

# --- assemble -----------------------------------------------------------------

template = File.read(File.join(DIR, "guide.template.html"))

paper = %w[paper_s1 paper_s2 paper_s31 paper_s313_s32 paper_s323b_s33 paper_s4a paper_s4b paper_s5 paper_s678]
        .map { |f| File.read(File.join(DIR, "paper", "#{f}.html")) }
        .join("\n")
html = template.sub("<!--@@PAPER@@-->") { paper }
html = replace_diagrams(html)
# Wide paper tables scroll inside their own container, never the page.
html = html.gsub(%r{(<table class="ptable"[^>]*>.*?</table>)}m) { %(<div class="tblwrap">#{Regexp.last_match(1)}</div>) }

# Code sections: segment name -> [backlink target id, label]
SEGMENT_HOME = {
  "Prelude" => %w[rb-prelude Cordis],
  "Effect" => %w[rb-effect Effect],
  "EffectContext" => %w[rb-effect-context EffectContext],
  "Independence" => %w[rb-independence Independence],
  "Satisfaction" => %w[rb-coeffect-context Satisfaction],
  "CoeffectContext" => %w[rb-coeffect-context CoeffectContext],
  "Coeffects" => %w[rb-coeffects Coeffects],
  "Coeffect" => %w[rb-coeffect Coeffect],
  "InterceptedContext" => %w[rb-interception InterceptedContext],
  "IsolatedContext" => %w[rb-isolated IsolatedContext],
  "Component" => %w[rb-component Component],
  "ActivationScope" => %w[rb-component ActivationScope],
  "System" => %w[rb-system System],
  "CalcPrelude" => %w[rb-calculus Calculus],
  "CalcComponent" => %w[rb-calculus-objects Calculus::Component],
  "CalcFiber" => %w[rb-calculus-objects Calculus::Fiber],
  "CalcMachine" => %w[rb-calculus-machine Calculus::Machine],
  "LoaderEntry" => %w[rb-loader-core Loader::Entry],
  "LoaderReconciler" => %w[rb-loader-core Loader::Reconciler],
  "LoaderHMR" => %w[rb-hmr Loader::HMR]
}.freeze

backlinks = Hash.new { |h, k| h[k] = [] }

def collect_backlinks(rendered, home, backlinks)
  rendered.scan(/href="#([^"]+)"/).flatten.uniq.each do |anchor|
    backlinks[anchor] << home unless backlinks[anchor].include?(home)
  end
end

cordis_segments.each do |name, (seg, first_line)|
  rendered = render_code(seg, first_line, "cordis.rb")
  collect_backlinks(rendered, SEGMENT_HOME.fetch(name), backlinks)
  html = html.sub("@@CODE:#{name}@@") { rendered }
end

calculus_segments.each do |name, (seg, first_line)|
  rendered = render_code(seg, first_line, "cordis_calculus.rb")
  collect_backlinks(rendered, SEGMENT_HOME.fetch(name), backlinks)
  html = html.sub("@@CODE:#{name}@@") { rendered }
end

loader_lines = File.readlines(File.join(DIR, "cordis_loader.rb"))
{
  "LoaderEntry" => extract(loader_lines, /\A    # Definition 74/, /\A    end$/),
  "LoaderReconciler" => extract(loader_lines, /\A    # The loader keeps/, /\A    end$/),
  "LoaderHMR" => extract(loader_lines, /\A    # -{5,}/, /\A    end$/)
}.each do |key, (seg, first_line)|
  rendered = render_code(seg, first_line, "cordis_loader.rb")
  collect_backlinks(rendered, SEGMENT_HOME.fetch(key), backlinks)
  html = html.sub("@@CODE:#{key}@@") { rendered }
end

checks_lines = File.readlines(File.join(DIR, "theorem_checks.rb"))
{
  "assign" => extract(checks_lines, /\A# --- Sample contexts/, /\Adef same_fn\?/, inclusive: false),
  "cor21" => extract(checks_lines, /\Acheck "Corollary 21/, /\Aend$/)
}.each do |key, (seg, first_line)|
  rendered = render_code(seg, first_line, "theorem_checks.rb")
  collect_backlinks(rendered, %w[rb-checks theorem_checks.rb], backlinks)
  html = html.sub("@@EXCERPT:#{key}@@") { rendered }
end

calc_checks_lines = File.readlines(File.join(DIR, "calculus_checks.rb"))
{
  "t63" => extract(calc_checks_lines, /\Acheck "Theorem 63/, /\Aend$/),
  "confluence" => extract(calc_checks_lines, /\Acheck "Theorem 73 \(dynamic/, /\Aend$/)
}.each do |key, (seg, first_line)|
  rendered = render_code(seg, first_line, "calculus_checks.rb")
  collect_backlinks(rendered, %w[rb-checks calculus_checks.rb], backlinks)
  html = html.sub("@@EXCERPT:#{key}@@") { rendered }
end

demo2_lines = File.readlines(File.join(DIR, "demo_reconcile.rb"))
demo2_rendered = render_code(demo2_lines.map(&:dup).tap { |l| l.pop while l.last&.strip&.empty? }, 1, "demo_reconcile.rb")
collect_backlinks(demo2_rendered, %w[rb-demo2 demo_reconcile.rb], backlinks)
html = html.sub("@@CODE:demo2@@") { demo2_rendered }

demo_lines = File.readlines(File.join(DIR, "demo_hot_swap.rb"))
demo_rendered = render_code(demo_lines.map(&:dup).tap { |l| l.pop while l.last&.strip&.empty? }, 1, "demo_hot_swap.rb")
collect_backlinks(demo_rendered, %w[rb-demo demo_hot_swap.rb], backlinks)
html = html.sub("@@CODE:demo@@") { demo_rendered }

checks_out = render_terminal("theorem_checks.rb", capture("theorem_checks.rb"))
calculus_out = render_terminal("calculus_checks.rb", capture("calculus_checks.rb"))
demo_out = render_terminal("demo_hot_swap.rb", capture("demo_hot_swap.rb"))
reconcile_out = render_terminal("demo_reconcile.rb", capture("demo_reconcile.rb"))
collect_backlinks(checks_out, %w[rb-checks theorem_checks.rb], backlinks)
collect_backlinks(calculus_out, %w[rb-checks calculus_checks.rb], backlinks)
collect_backlinks(demo_out, %w[rb-demo demo_hot_swap.rb], backlinks)
collect_backlinks(reconcile_out, %w[rb-demo2 demo_reconcile.rb], backlinks)
html = html.sub("@@OUT:checks@@") { checks_out }
html = html.sub("@@OUT:calculus@@") { calculus_out }
html = html.sub("@@OUT:demo@@") { demo_out }
html = html.sub("@@OUT:reconcile@@") { reconcile_out }

# Inject "In the Ruby" rows into the cited paper blocks.
html = html.gsub(/<!--BL:([\w-]+)-->/) do
  anchor = Regexp.last_match(1)
  homes = backlinks[anchor]
  next "" if homes.empty?

  chips = homes.map { |(id, label)| %(<a class="bl" href="##{id}">#{label}</a>) }.join(" ")
  %(<p class="bl-row"><span class="bl-label">In the Ruby</span> #{chips}</p>)
end

# --- verify -------------------------------------------------------------------

leftover = html.scan(/@@[A-Z]+:[\w.-]+@@|<!--@@[A-Z]+@@-->/)
abort "build: unresolved markers: #{leftover.uniq.join(", ")}" unless leftover.empty?

ids = html.scan(/id="([^"]+)"/).flatten
dupes = ids.tally.select { |_, n| n > 1 }.keys
abort "build: duplicate ids: #{dupes.join(", ")}" unless dupes.empty?

hrefs = html.scan(/href="#([^"]+)"/).flatten.uniq
missing = hrefs - ids
abort "build: dangling links: #{missing.join(", ")}" unless missing.empty?

File.write(File.join(DIR, "index.html"), html)
puts "index.html written: #{(html.bytesize / 1024.0).round}KB, #{ids.length} anchors, #{hrefs.length} distinct link targets, all resolved."
