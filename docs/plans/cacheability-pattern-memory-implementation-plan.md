# Cacheability and Pattern Memory Implementation Plan

## Objective

Implement ADR 0013 so persisted artifacts remain durable without semantic cache poisoning, while enabling emergent promotion by giving the Agent explicit pattern memory.

This plan preserves:

1. Stable artifact identity (`role + method_name`) from ADR 0012.
2. Agent-first promotion decisions (runtime provides observations, not decisions).
3. Tolerant interface behavior and typed Outcome semantics.

## Scope

In scope:

1. Cacheability metadata and reuse gating for persisted artifacts.
2. Runtime capability-pattern extraction from generated code.
3. Bounded cross-call pattern memory persistence.
4. Prompt injection of `<recent_patterns>` for depth-0 calls.
5. Observability, tests, and evaluation loops for promotion quality.

Out of scope:

1. Runtime-autonomous promotion (runtime forcing Forge).
2. Semantic LLM classification in v1 pattern extraction.
3. Lua runtime parity.

## Current State Snapshot

Already implemented:

1. Artifact cacheability metadata (`cacheable`, `cacheability_reason`, `input_sensitive`).
2. Reuse gate in artifact selector (non-cacheable artifacts are persisted but not reused).
3. Legacy compatibility fallback (dynamic methods not reused when cacheability metadata is absent).
4. Dynamic dispatch method set (`ask`, `chat`, `discuss`, `host`) as non-cacheable by default.
5. Call-level logging fields for cacheability.

Remaining for ADR 0013 completion:

1. Pattern extraction and persistence.
2. `<recent_patterns>` prompt injection.
3. Promotion-signal evaluation and threshold tuning.

## Design Constraints

1. Artifact identity remains `role + method_name`; do not expand key shape.
2. Runtime controls execution eligibility; model cannot force cacheable reuse.
3. Pattern memory contains labels/counts/recency only; never inject prior raw code.
4. Pattern memory must be bounded and deterministic.
5. Runtime ergonomics first: keep implementation simple, inspectable, and recoverable.

## Delivery Strategy

Deliver in five phases. Each phase is testable and independently valuable.

### Phase 0: Contract and Baseline

Goals:

1. Establish deterministic capability tag set and extraction contract.
2. Capture baseline behavior for Google/Yahoo/NYT sequence before pattern injection.

Implementation:

1. Define capability tags (initial v1 list):
   - `http_fetch`
   - `rss_parse`
   - `xml_parse`
   - `html_extract`
   - `news_headline_extract`
   - Keep this list intentionally small; do not add speculative tags. Add tags only when traces show a missed promotion signal.
2. Define deterministic extraction sources:
   - `require 'rss'` -> `rss_parse`
   - `RSS::Parser` -> `rss_parse`
   - `require 'rexml/document'` or `REXML::Document` -> `xml_parse`
   - `Net::HTTP` use or `tool("web_fetcher")` -> `http_fetch`
   - collection iteration that extracts both `title` and `link` fields into structured output -> `news_headline_extract`
3. Capture baseline traces from:
   - [`runtimes/ruby/examples/assistant.rb`](../../runtimes/ruby/examples/assistant.rb)
   - prompts: Google News, Yahoo News, NYT.

Exit criteria:

1. Capability extraction contract documented and reviewed.
2. Baseline trace fixture committed under `docs/baselines/<date>/`.

### Phase 1: Capability Extraction Pipeline

Goals:

1. Tag each generated/repaired call with deterministic capability labels.
2. Keep extraction local and low-latency.

Implementation:

1. Add `CapabilityPatternExtractor` module:
   - input: method name, role, generated code, args/kwargs, outcome.
   - output: label array + extraction evidence.
2. Integrate extractor in call flow after generated code capture (and after repaired code generation).
3. Emit extracted labels into log entry.

Suggested files:

1. [`runtimes/ruby/lib/recurgent/capability_pattern_extractor.rb`](../../runtimes/ruby/lib/recurgent/capability_pattern_extractor.rb)
2. [`runtimes/ruby/lib/recurgent/call_state.rb`](../../runtimes/ruby/lib/recurgent/call_state.rb)
3. [`runtimes/ruby/lib/recurgent/call_execution.rb`](../../runtimes/ruby/lib/recurgent/call_execution.rb)
4. [`runtimes/ruby/lib/recurgent/artifact_repair.rb`](../../runtimes/ruby/lib/recurgent/artifact_repair.rb)
5. [`runtimes/ruby/lib/recurgent/observability.rb`](../../runtimes/ruby/lib/recurgent/observability.rb)

Exit criteria:

1. Every generated/repaired call log includes `capability_patterns`.
2. Extraction is deterministic for fixed code input.

### Phase 2: Pattern Memory Store

Goals:

1. Persist bounded recent pattern history across sessions.
2. Provide fast read API for prompt assembly.

Implementation:

1. Add pattern store file:
   - `tools/patterns.json`
2. Store schema (v1):
   - `schema_version`
   - per-role rolling events (max N, default 50)
   - per-role aggregate counts for recent windows (for example 5 and 10)
3. Event record shape:
   - `timestamp`
   - `role`
   - `method_name`
   - `capability_patterns[]`
   - `outcome_status`
   - `error_type`
4. Write policy:
   - append logical event, trim by retention cap, atomic temp+rename write.
5. Read API:
   - `recent_patterns_for(role:, method_name:, window:)` returning count summaries.

Suggested files:

1. [`runtimes/ruby/lib/recurgent/pattern_memory_store.rb`](../../runtimes/ruby/lib/recurgent/pattern_memory_store.rb)
2. [`runtimes/ruby/lib/recurgent/tool_store_paths.rb`](../../runtimes/ruby/lib/recurgent/tool_store_paths.rb) (path helper)
3. [`runtimes/ruby/lib/recurgent/call_execution.rb`](../../runtimes/ruby/lib/recurgent/call_execution.rb) (write hook)

Exit criteria:

1. Pattern memory survives process restart.
2. Corrupt file quarantine behavior mirrors registry/artifact strategy.

### Phase 3: Prompt Injection (`<recent_patterns>`)

Goals:

1. Expose repetition signal to the depth-0 agent.
2. Keep prompt block concise and non-prescriptive.

Implementation:

1. Add prompt builder method:
   - only for depth-0 calls,
   - primarily for dynamic dispatch methods (for example `ask`).
2. Inject block format:

```xml
<recent_patterns>
- rss_parse: seen 3 of last 5 ask calls, tool_present=false
- http_fetch: seen 5 of last 5 ask calls, tool_present=true(web_fetcher)
</recent_patterns>
```

3. Add nudge language:
   - "If a general capability repeats and no Tool exists, consider Forging now."
4. Ensure no raw code inclusion in this block.

Suggested files:

1. [`runtimes/ruby/lib/recurgent/prompting.rb`](../../runtimes/ruby/lib/recurgent/prompting.rb)
2. [`runtimes/ruby/lib/recurgent/known_tool_ranker.rb`](../../runtimes/ruby/lib/recurgent/known_tool_ranker.rb) (optional utility reuse)
3. [`runtimes/ruby/lib/recurgent/call_execution.rb`](../../runtimes/ruby/lib/recurgent/call_execution.rb) (pass method context to prompt builder if needed)

Exit criteria:

1. Debug logs show `<recent_patterns>` for depth-0 dynamic calls.
2. Block is absent for depth>0 and bounded to top-N entries.

### Phase 4: Promotion Signal Evaluation and Tuning

Goals:

1. Verify that pattern memory increases coherent promotion events.
2. Tune thresholds without runtime-autonomous promotion.

Implementation:

1. Add derived observability metrics:
   - `promotion_candidate_detected` (boolean)
   - `promotion_candidate_capabilities[]`
   - `tool_forged_this_call` (already inferable via registry delta)
2. Evaluate scenarios:
   - repeated news queries (Google, Yahoo, NYT, BBC),
   - repeated RSS-like feeds from varied domains.
   - unrelated dynamic queries (for example news -> timezone -> haiku) to validate low false-positive promotion signaling.
3. Tune defaults:
   - initial recommendation: promote general capability at 2+ observed repeats in last 5.

Exit criteria:

1. Demonstrated increase in coherent reusable tool creation (for example `rss_parser` emergence).
2. No regression in dynamic-method correctness (no cross-query semantic leakage).

## Data Contracts

### Pattern Memory File (`tools/patterns.json`)

```json
{
  "schema_version": 1,
  "roles": {
    "personal assistant that remembers conversation history": {
      "events": [
        {
          "timestamp": "2026-02-15T07:00:00.000Z",
          "method_name": "ask",
          "capability_patterns": ["http_fetch", "rss_parse", "news_headline_extract"],
          "outcome_status": "ok",
          "error_type": null
        }
      ]
    }
  }
}
```

Constraints:

1. Events are newest-last or newest-first (choose one, document clearly).
2. Retention cap enforced per role.
3. JSON-serializable primitives only.

## Test Strategy

### Unit Tests

1. `CapabilityPatternExtractor` mapping:
   - RSS code -> `rss_parse`
   - REXML code -> `xml_parse`
   - HTTP fetch patterns -> `http_fetch`
2. Pattern store:
   - read/write/trim behavior,
   - atomic write,
   - corrupt-file quarantine and recovery.
3. Prompt rendering:
   - includes `<recent_patterns>` only when applicable,
   - excludes raw prior code.

### Integration Tests

1. Dynamic method non-reuse:
   - `ask("Google")` then `ask("Yahoo")` must generate twice.
2. Stable tool reuse remains intact:
   - `web_fetcher.fetch_url(url1/url2)` can reuse artifact.
3. Pattern-memory persistence:
   - restart process; `<recent_patterns>` still reflects prior calls.

### Acceptance Tests

1. News sequence:
   - Google -> Yahoo -> NYT
   - verify pattern block appears and evolves.
2. Promotion behavior:
   - verify tool registry gains generalized parser tool in repeated-capability scenario (non-deterministic; validate with seeded deterministic provider tests + manual trace validation).
3. Negative promotion case:
   - run unrelated dynamic `ask` sequence and verify pattern memory does not emit spurious promotion candidates.

## Rollout and Operational Controls

1. Ship Phase 1+2 first (observation only, no prompt injection) if needed for safe validation.
2. Enable Phase 3 prompt injection once pattern data quality is acceptable.
3. Keep runtime read-path behavior unchanged during Phase 1-2.
4. Add maintenance command extension (optional):
   - `bin/recurgent-tools patterns --role <role> --window 5`

## Risks and Mitigations

1. Risk: noisy/incorrect capability tagging.
   - Mitigation: start with deterministic regex + stdlib require signals; evolve taxonomy cautiously.
2. Risk: prompt bloat.
   - Mitigation: strict top-N and short label summaries.
3. Risk: over-promotion due to shallow patterns.
   - Mitigation: require repeated counts + no-existing-tool condition in prompt nudge.
4. Risk: hidden coupling to implementation syntax.
   - Mitigation: maintain extractor fixtures across known code variants.

## Completion Checklist

1. [ ] Capability extractor implemented and tested.
2. [ ] Pattern memory store implemented and tested.
3. [ ] `<recent_patterns>` prompt injection implemented and tested.
4. [ ] Observability fields and watcher support updated.
5. [ ] End-to-end news sequence validated with trace evidence.
6. [ ] Baseline comparison committed: pre/post pattern-memory traces for Google/Yahoo/NYT showing promotion behavior change.
7. [ ] ADR 0013 status reviewed for `accepted` transition after stable rollout.
