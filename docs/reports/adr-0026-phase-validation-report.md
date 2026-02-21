# ADR 0026 Phase Validation Report

- Date: 2026-02-21
- Scope: [`docs/plans/response-content-continuity-implementation-plan.md`](../plans/response-content-continuity-implementation-plan.md)
- Required checks per phase:
  1. Full Ruby test suite (`bundle exec rspec`)
  2. Calculator example ([`runtimes/ruby/examples/calculator.rb`](../../runtimes/ruby/examples/calculator.rb))
  3. Assistant example ([`runtimes/ruby/examples/assistant.rb`](../../runtimes/ruby/examples/assistant.rb)) with:
     - `What's the top news items in Google News, Yahoo! News, and NY Times`
     - `What's are the action adventure movies playing in theaters`
     - `What's a good recipe for Jaffna Kool`
  4. Log inspection and diagnosis after calculator + assistant runs

## Phase 0

### Changes

- Baseline capture only for ADR 0026 (no runtime behavior change yet).
- Validation artifacts captured under [`tmp/phase-validation-0026/phase-0/`](../../tmp/phase-validation-0026/phase-0).

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-0/xdg bundle exec rspec`
- Result: PASS
- Evidence: [`tmp/phase-validation-0026/phase-0/rspec.txt`](../../tmp/phase-validation-0026/phase-0/rspec.txt)
- Summary:
  - `265 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-0/xdg ruby examples/calculator.rb`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0026/phase-0/calculator.txt`](../../tmp/phase-validation-0026/phase-0/calculator.txt)
- Output checks:
  - `add(3) => 8` (correct)
  - `multiply(4) => 32` (correct)
  - `sqrt(32) => 5.656854249492381` (correct)
  - `sqrt(144) => 12.0` (correct)
  - `factorial(10) => 3628800` (correct)
  - `convert(100, celsius->fahrenheit) => 212.0` (correct)
  - `solve('2x + 5 = 17') => guardrail_retry_exhausted` (incorrect/unresolved)
  - `history => guardrail_retry_exhausted` at output path, with fallback to runtime context history dump
- Accuracy assessment:
  - Core arithmetic path is correct.
  - Equation-solver path and history method are unstable at baseline.

#### Assistant example

- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-0/xdg ruby examples/assistant.rb < /Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-0/assistant_input.txt`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0026/phase-0/assistant.txt`](../../tmp/phase-validation-0026/phase-0/assistant.txt)
- Request 1 (top news):
  - Returned Google News + NY Times feeds with item lists.
  - Yahoo! News failed with `HTTP 308 Permanent Redirect` and surfaced in returned `errors`.
  - Accuracy: partial source coverage; provenance present for successful sources.
- Request 2 (action-adventure movies in theaters):
  - Returned `capability_unavailable` with explicit limitation explanation.
  - Accuracy: truthful boundary response, but user request unsatisfied.
- Request 3 (Jaffna Kool recipe):
  - Returned structured recipe payload (`dish`, `ingredients`, `instructions`, `tips`).
  - Accuracy: plausible and useful.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation-0026/phase-0/xdg/recurgent/recurgent.jsonl` (`15` entries)
- Trace summary:
  - Roles:
    - `calculator`: `8`
    - `personal assistant that remembers conversation history`: `3`
    - `rss_feed_fetcher`: `3`
    - `unit_converter`: `1`
  - Top-level outcomes:
    - calculator: `6 ok`, `2 error(guardrail_retry_exhausted)`
    - assistant ask: `ok`, `error(capability_unavailable)`, `ok`
- What went well:
  - Baseline suite is green (`265/265`).
  - Arithmetic and recipe flows are healthy.
  - News path returns structured payload with provenance for successful sources.
- What needs improvement:
  - Calculator `solve` and `history` still exhibit guardrail exhaustion.
  - News retrieval needs resilient Yahoo redirect handling.
  - Movie-theater query remains unsupported by available capabilities.

## Phase 1

### Changes

- Added response content store substrate:
  - [`runtimes/ruby/lib/recurgent/content_store.rb`](../../runtimes/ruby/lib/recurgent/content_store.rb)
- Linked successful outcomes to content continuity refs in conversation history:
  - `outcome_summary.content_ref`
  - `outcome_summary.content_kind`
  - `outcome_summary.content_bytes`
  - `outcome_summary.content_digest`
- Added depth-aware default write policy:
  - depth `0` successful outcomes stored by default.
  - depth `>= 1` writes disabled unless `content_store_nested_capture_enabled` is explicitly enabled.
- Added runtime config knobs:
  - `content_store_max_entries`
  - `content_store_max_bytes`
  - `content_store_ttl_seconds`
  - `content_store_nested_capture_enabled`
  - `content_store_store_error_payloads`
- Added observability fields for content-store write metadata in call logs.
- Added tests for:
  - content-ref summary emission on success,
  - depth-aware nested capture default behavior,
  - explicit nested-capture opt-in behavior.

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-1/xdg bundle exec rspec`
- Result: PASS
- Evidence: [`tmp/phase-validation-0026/phase-1/rspec.txt`](../../tmp/phase-validation-0026/phase-1/rspec.txt)
- Summary:
  - `268 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-1/xdg ruby examples/calculator.rb`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0026/phase-1/calculator.txt`](../../tmp/phase-validation-0026/phase-1/calculator.txt)
- Output checks:
  - `add(3) => 8.0` (correct)
  - `multiply(4) => 20.0` (incorrect; expected chained memory behavior gave `32` in baseline)
  - `sqrt(20.0) => 4.47213595499958` (mathematically correct for the upstream value)
  - `sqrt(144) => 12.0` (correct)
  - `factorial(10) => 3628800` (correct)
  - `convert(100, celsius->fahrenheit) => 212.0` (correct)
  - `solve('2x + 5 = 17') => -2.5` (incorrect)
  - `history => guardrail_retry_exhausted` at output path, with fallback to runtime context history dump
- Accuracy assessment:
  - Content continuity metadata appears on successful calculator records.
  - Calculator semantic stability remains inconsistent and independent of content-store linkage.

#### Assistant example

- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-1/xdg ruby examples/assistant.rb < /Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-1/assistant_input.txt`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0026/phase-1/assistant.txt`](../../tmp/phase-validation-0026/phase-1/assistant.txt)
- Request 1 (top news):
  - Returned Google News + NY Times lists.
  - Yahoo! News failed with `403 Forbidden`.
  - Accuracy: partial source coverage; still useful with provenance for successful sources.
- Request 2 (action-adventure movies in theaters):
  - Returned a non-empty explanatory message, but outcome trace still reflected error semantics.
  - Accuracy: request remains unsatisfied.
- Request 3 (Jaffna Kool recipe):
  - Returned structured recipe payload with provenance.
  - Accuracy: useful and plausible.
- Notable runtime warning:
  - JSON encoding warning from generated code path (`UTF-8 string passed as BINARY`) observed during run.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation-0026/phase-1/xdg/recurgent/recurgent.jsonl` (`21` entries)
- Trace summary:
  - Roles:
    - `calculator`: `8`
    - `personal assistant that remembers conversation history`: `3`
    - `web_fetcher`: `3`
    - `news_parser`: `2`
    - `theater_movie_finder`: `4`
    - `recipe_search_tool`: `1`
  - Content-store write metrics:
    - `content_store_write_applied=true`: `9` entries
    - unique `content_store_write_ref`: `9`
    - depth `0`: `11` calls, `9` writes
    - depth `1`: `10` calls, `0` writes (expected default behavior)
- What went well:
  - Content refs now emitted and persisted for successful top-level outcomes.
  - Depth-aware write policy behaved as expected in traces (nested writes suppressed by default).
  - Full suite remained green after substrate integration.
- What needs improvement:
  - Calculator behavior regressed semantically on multiply/solve despite stable infrastructure.
  - Assistant still lacks robust theater-showtimes capability.
  - Generated-code encoding hygiene needs tightening to avoid JSON/BINARY warnings.

## Phase 2

### Changes

- Added generated-code retrieval helper:
  - `content(ref)` available in execution sandbox via [`runtimes/ruby/lib/recurgent/execution_sandbox.rb`](../../runtimes/ruby/lib/recurgent/execution_sandbox.rb)
- Prompt integration updates:
  - Environment model now describes `content(ref)` semantics.
  - Decomposition guidance includes explicit content-follow-up handling flow.
  - Conversation-history schema now documents `content_ref/content_kind/content_bytes/content_digest`.
  - Added content-followup example pattern in prompt examples.
- Added spec coverage for:
  - prompt inclusion of content helper guidance,
  - successful prior payload resolution via `content(ref)`,
  - typed `content_ref_not_found` handling on misses.

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-2/xdg bundle exec rspec`
- Result: PASS
- Evidence: [`tmp/phase-validation-0026/phase-2/rspec.txt`](../../tmp/phase-validation-0026/phase-2/rspec.txt)
- Summary:
  - `271 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-2/xdg ruby examples/calculator.rb`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0026/phase-2/calculator.txt`](../../tmp/phase-validation-0026/phase-2/calculator.txt)
- Output checks:
  - `add(3) => 8.0` (correct)
  - `multiply(4) => 32.0` (correct)
  - `sqrt(32.0) => 5.656854249492381` (correct)
  - `sqrt(144) => 12.0` (correct)
  - `factorial(10) => 3628800` (correct)
  - `convert(100, celsius->fahrenheit) => 212.0` (correct)
  - `solve('2x + 5 = 17') => guardrail_retry_exhausted` (incorrect/unresolved)
  - `history => guardrail_retry_exhausted` at output path, with fallback to runtime context history dump
- Accuracy assessment:
  - Arithmetic path recovered in this phase.
  - `solve` and `history` remain guardrail-unstable.

#### Assistant example

- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-2/xdg ruby examples/assistant.rb < /Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-2/assistant_input.txt`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0026/phase-2/assistant.txt`](../../tmp/phase-validation-0026/phase-2/assistant.txt)
- Request 1 (top news):
  - Returned Yahoo + NY Times items.
  - Google parsing path failed (`content is empty or nil`) and surfaced as an error entry.
  - Accuracy: partial source success with clear failure disclosure.
- Request 2 (action-adventure movies in theaters):
  - Returned `capability_unavailable`.
  - Accuracy: truthful limitation, request unsatisfied.
- Request 3 (Jaffna Kool recipe):
  - Returned structured recipe with provenance.
  - Accuracy: useful and plausible.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation-0026/phase-2/xdg/recurgent/recurgent.jsonl` (`19` entries)
- Trace summary:
  - Roles:
    - `calculator`: `8`
    - `personal assistant that remembers conversation history`: `3`
    - `web_fetcher`: `5`
    - `content_parser`: `3`
  - Content-store metrics:
    - `content_store_write_applied=true`: `8`
    - depth `0`: `11` calls
    - depth `1`: `8` calls
    - `content_store_read_hit_count`: `0` (in this mandatory scenario set)
    - `content_store_read_miss_count`: `0`
- What went well:
  - Prompt/runtime retrieval surfaces landed without regressions.
  - Content refs continued to emit for successful top-level outcomes.
  - New retrieval tests passed in suite.
- What needs improvement:
  - Mandatory scenario set does not naturally exercise follow-up content retrieval; add dedicated acceptance traces for `content(ref)` flows in next iteration.
  - Live news-source robustness still varies by source/parser path.

## Phase 3

### Changes

- Added content-store read observability capture:
  - per-call `content_store_read_hit_count`
  - per-call `content_store_read_miss_count`
  - per-call `content_store_read_refs`
  - `content_store_eviction_count`
- Added skip-reason tracking for non-written payload cases (`nested_capture_disabled`, etc.).
- Added governance hook for retention-policy mutation through proposal authority lanes:
  - proposal type: `content_retention_policy_update`
  - apply path integrated with `approve_proposal`/`apply_proposal` flow and authority checks.
- Added tests for:
  - content-read telemetry logging
  - proposal-driven content retention policy mutation.

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-3/xdg bundle exec rspec`
- Result: PASS
- Evidence: [`tmp/phase-validation-0026/phase-3/rspec.txt`](../../tmp/phase-validation-0026/phase-3/rspec.txt)
- Summary:
  - `273 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-3/xdg ruby examples/calculator.rb`
- Result: PARTIAL (regressed)
- Evidence: [`tmp/phase-validation-0026/phase-3/calculator.txt`](../../tmp/phase-validation-0026/phase-3/calculator.txt)
- Output checks:
  - `add(3) => 8.0` (correct)
  - `multiply(4) => 32.0` (correct)
  - `sqrt(32.0) => 5.656854249492381` (correct)
  - `sqrt(144) => guardrail_retry_exhausted` (regression)
  - `factorial(10) => guardrail_retry_exhausted` (regression)
  - `convert(100, celsius->fahrenheit) => guardrail_retry_exhausted` (regression)
  - `solve('2x + 5 = 17') => guardrail_retry_exhausted` (regression)
  - `history => guardrail_retry_exhausted`
- Accuracy assessment:
  - Early arithmetic remained correct.
  - Overall calculator reliability regressed sharply in this run due repeated guardrail exhaustion.

#### Assistant example

- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-3/xdg ruby examples/assistant.rb < /Users/kulesh/dev/actuator/tmp/phase-validation-0026/phase-3/assistant_input.txt`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0026/phase-3/assistant.txt`](../../tmp/phase-validation-0026/phase-3/assistant.txt)
- Request 1 (top news):
  - Returned Yahoo + NY Times.
  - Google path failed (`rss_feed_fetcher.fetch_feed` exhausted outcome-error repairs).
  - Accuracy: partial source success with explicit error transparency.
- Request 2 (action-adventure movies in theaters):
  - Returned `capability_unavailable`.
  - Accuracy: truthful limitation, request unsatisfied.
- Request 3 (Jaffna Kool recipe):
  - Returned a structured recipe-like response, but framed as a cooling beverage variant rather than the commonly expected seafood soup form.
  - Accuracy: partially useful but semantically drifted from expected dish form.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation-0026/phase-3/xdg/recurgent/recurgent.jsonl` (`14` entries)
- Trace summary:
  - Roles:
    - `calculator`: `8`
    - `personal assistant that remembers conversation history`: `3`
    - `rss_feed_fetcher`: `3`
  - Content-store metrics:
    - `content_store_write_applied=true`: `5`
    - `content_store_read_hit_count`: `0`
    - `content_store_read_miss_count`: `0`
    - `content_store_eviction_count`: `0`
    - `content_store_write_skipped_reason` tally: `{ "nested_capture_disabled": 2 }`
- What went well:
  - Observability fields emitted and queryable in logs.
  - Governance mutation lane implemented and validated through tests.
  - Nested write suppression remained explicit and explainable.
- What needs improvement:
  - Calculator guardrail resilience regressed in this live run.
  - Mandatory scenario set still does not exercise content-read behavior directly.

## Supplemental Continuity Check

- Scenario: "Write a quick sort algorithm in Smalltalk?" then "format the quick sort algorithm in markdown"
- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0026/content-followup-check/xdg ruby examples/assistant.rb < /Users/kulesh/dev/actuator/tmp/phase-validation-0026/content-followup-check/input.txt`
- Evidence:
  - [`tmp/phase-validation-0026/content-followup-check/output.txt`](../../tmp/phase-validation-0026/content-followup-check/output.txt)
  - `tmp/phase-validation-0026/content-followup-check/xdg/recurgent/recurgent.jsonl`
- Result:
  - Second turn succeeded and produced markdown output.
  - Log evidence confirmed ref-resolution read path:
    - second call `content_store_read_hit_count=1`
    - `content_store_read_refs=["content:b574314dd1e65fc7cc12e036"]`

## Final Rollup (All Phases)

### Expected Improvements vs Observed

1. Expected: attach stable `content_ref` metadata to successful outcomes.
   - Observed: achieved from Phase 1 onward; refs present across successful top-level calls.
2. Expected: keep nested (`depth>=1`) writes suppressed by default.
   - Observed: achieved; depth-1 writes remained zero in phase traces unless explicitly enabled by config.
3. Expected: enable follow-up content retrieval through runtime helper.
   - Observed: achieved in automated specs and supplemental continuity check (read hit observed in live trace).
4. Expected: improve explainability of continuity behavior via logs.
   - Observed: achieved; write/read counters, refs, and skip reasons are now visible in JSONL telemetry.
5. Expected: keep baseline reliability stable while adding substrate.
   - Observed: mixed; test suite remained green each phase, but live calculator semantics were unstable and regressed in Phase 3 run.

### What Improved

1. Response content continuity is now first-class:
   - storage,
   - reference linkage,
   - retrieval helper,
   - observability.
2. Prompt model now explicitly teaches content-followup flow.
3. Governance lanes now support retention-policy mutation through authority-controlled proposals.

### What Did Not Improve (or Regressed)

1. Calculator example reliability remains inconsistent run-to-run (`guardrail_retry_exhausted` spikes).
2. Assistant live-source coverage remains partial in news aggregation (source-specific failures vary by run).
3. Theater-showtimes capability remains unavailable in current tool boundary.

### Core Learning

1. ADR 0026 substrate changes delivered continuity mechanics and observability.
2. Mechanical continuity does not by itself guarantee semantic robustness in generated tool logic.
3. Next quality gains need targeted prompt/guardrail and tool-quality work on high-variance examples (calculator solve/history and live-source adapters), not additional continuity plumbing.
