# ADR 0023 Phase Validation Report

- Date: 2026-02-19
- Scope: `docs/plans/solver-shape-reliability-gated-tool-evolution-implementation-plan.md`
- Required checks per phase:
  1. Full Ruby test suite (`bundle exec rspec`)
  2. Calculator example (`runtimes/ruby/examples/calculator.rb`)
  3. Assistant example (`runtimes/ruby/examples/assistant.rb`) with three requests:
     - What's the top news items in Google News, Yahoo! News, and NY Times
     - What's are the action adventure movies playing in theaters
     - What's a good recipe for Jaffna Kool
  4. Log inspection and diagnosis for calculator + assistant runs

## Phase 0

### Changes

- Added ADR and plan documents for solver-shape and reliability-gated tool evolution.
- Updated documentation indexes.

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-0/xdg bundle exec rspec`
- Result: PASS
- Evidence: `tmp/phase-validation/phase-0/rspec.txt`
- Summary:
  - `238 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-0/xdg ruby examples/calculator.rb`
- Result: PASS
- Evidence: `tmp/phase-validation/phase-0/calculator.txt`
- Output checks:
  - `add(3) => 8`
  - `multiply(4) => 32`
  - `sqrt(32) => 5.656854249492381`
  - `sqrt(144) => 12.0`
  - `factorial(10) => 3628800`
  - `convert(100, celsius->fahrenheit) => 212.0`
  - `solve('2x + 5 = 17') => x = 6.0`
- Accuracy assessment: Correct for all numeric operations shown.

#### Assistant example

- Command: `cd runtimes/ruby && printf ... | XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-0/xdg ruby examples/assistant.rb`
- Result: PARTIAL
- Evidence: `tmp/phase-validation/phase-0/assistant.txt`
- Request 1 (top news from Google/Yahoo/NYT):
  - Returned 15 items (5 per source) with provenance entries for all 3 source feeds.
  - Accuracy: Structurally correct with source coverage and provenance present.
- Request 2 (action adventure movies in theaters):
  - Returned typed error: `capability_unavailable`.
  - Accuracy: Not meeting user request content, but truthful failure (no fabricated listings).
- Request 3 (Jaffna Kool recipe):
  - Returned detailed structured recipe payload with ingredients/instructions.
  - Accuracy: Plausible and useful recipe response.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation/phase-0/xdg/recurgent/recurgent.jsonl` (`18` entries)
- Calculator trace (8 entries, all `ok`, depth `0`):
  - Methods executed: `add`, `multiply`, `sqrt`, `sqrt`, `factorial`, `convert`, `solve`, `history`
  - Program source: all `generated`, no retries/exhaustion events.
- Assistant trace (3 top-level `ask` entries):
  - Call 1 (`ok`): delegated to `http_fetcher.fetch_url` and `rss_parser.parse` (3 fetch + 3 parse calls; first generated then persisted artifact reuse).
  - Call 2 (`error`): `capability_unavailable` with explicit message about missing live movie/showtime capability.
  - Call 3 (`ok`): recipe response generated directly.
- Diagnosis:
  - What went well:
    - Provenance-backed news aggregation succeeded and reused delegated artifacts within the session.
    - Calculator baseline behavior remains stable and correct.
    - Failure posture is honest (`capability_unavailable`) instead of hallucinated movie data.
  - Needs improvement:
    - Movie listings flow needs a tolerant fallback path (for example, currently-playing action/adventure discovery via available web/RSS sources) instead of hard failure.

## Phase 1

### Changes

- Implemented observational solver-shape capture in call state:
  - `solver_shape` fields: `stance`, `capability_summary`, `reuse_basis`, `contract_intent`, `promotion_intent`
  - `solver_shape_complete` boolean guardrail for required gate fields
- Wired solver-shape fields into JSONL observability:
  - `solver_shape`
  - `solver_shape_complete`
  - `solver_shape_stance`
  - `solver_shape_promotion_intent`
- Added logging spec coverage for new solver-shape fields.

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-1/xdg bundle exec rspec`
- Result: PASS
- Evidence: `tmp/phase-validation/phase-1/rspec.txt`
- Summary:
  - `238 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-1/xdg ruby examples/calculator.rb`
- Result: PARTIAL
- Evidence: `tmp/phase-validation/phase-1/calculator.txt`
- Output checks:
  - `add(3) => 3`
  - `multiply(4) => 12`
  - `sqrt(12) => 3.4641016151377544`
  - `sqrt(144) => 12.0`
  - `factorial(10) => 3628800`
  - `convert(100, celsius->fahrenheit) => 212.0`
  - `solve('2x + 5 = 17') => x = 6.0`
- Accuracy assessment:
  - Arithmetic chain semantics regressed for `add/multiply` relative to expected memory-based behavior.
  - Remaining calculations were accurate.

#### Assistant example

- Command: `cd runtimes/ruby && printf ... | XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-1/xdg ruby examples/assistant.rb`
- Result: PARTIAL
- Evidence: `tmp/phase-validation/phase-1/assistant.txt`
- Request 1 (top news):
  - Returned multi-source payload with Google/Yahoo/NYT and provenance.
  - Accuracy: Good overall source coverage and structure.
- Request 2 (action-adventure movies in theaters):
  - Returned `capability_unavailable`.
  - Accuracy: Truthful failure, but missing requested listings.
- Request 3 (Jaffna Kool recipe):
  - Returned structured recipe details.
  - Accuracy: Useful and plausible.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation/phase-1/xdg/recurgent/recurgent.jsonl` (`18` entries)
- Solver-shape telemetry verification:
  - `solver_shape` present on all 18 entries.
  - `solver_shape_complete=true` on all 18 entries.
  - Top-level calculator calls logged `stance=shape`, `promotion_intent=local_pattern`.
  - Top-level assistant calls logged `stance=forge`, `promotion_intent=durable_tool_candidate`.
- Execution trace highlights:
  - Calculator: 8 top-level calls + 1 delegated `calculator_tool.sqrt`.
  - Assistant news flow attempted `http_fetcher.fetch_url` (3 failures: guardrail/provenance), then succeeded with `rss_news_fetcher.fetch` (generated then persisted reuse).
- Diagnosis:
  - What went well:
    - Solver-shape observational fields were captured consistently with no test regressions.
    - Assistant recovered from one delegate lane to a working fallback lane for news.
  - Needs improvement:
    - Calculator behavior variability indicates weak contract anchoring for additive/multiplicative state semantics.
    - News flow still shows upstream tool-quality instability (guardrail/provenance failures before successful fallback).

## Phase 2

### Changes

- Added version-scoped artifact scorecards (`artifact["scorecards"][checksum]`) with:
  - calls/successes/failures
  - contract pass/fail counters
  - guardrail/outcome exhaustion counters
  - wrong-boundary and provenance-violation counters
  - short/medium rolling windows
  - session tracking
  - `state_key_consistency_ratio`
- Added registry metadata enrichment in `ToolStore`:
  - `method_state_keys`
  - `state_key_consistency_ratio`
  - `version_scorecards` keyed by `method@artifact_checksum`
- Added helper accessors for artifact scorecards and extended specs for scorecard/coherence persistence.

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-2/xdg bundle exec rspec`
- Result: PASS
- Evidence: `tmp/phase-validation/phase-2/rspec.txt`
- Summary:
  - `239 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-2/xdg ruby examples/calculator.rb`
- Result: PARTIAL
- Evidence: `tmp/phase-validation/phase-2/calculator.txt`
- Output checks:
  - `add(3) => 8`, `multiply(4) => 32`, `sqrt(32) => 5.656854249492381`
  - `sqrt(144) => 12.0`, `factorial(10) => 3628800`, `convert(...) => 212.0`
  - `solve('2x + 5 = 17') => { error_type: \"parse_error\", ... }`
- Accuracy assessment:
  - Core arithmetic path mostly correct.
  - Equation-solving path regressed to parse error, so example is not fully correct.

#### Assistant example

- Command: `cd runtimes/ruby && printf ... | XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-2/xdg ruby examples/assistant.rb`
- Result: PARTIAL
- Evidence: `tmp/phase-validation/phase-2/assistant.txt`
- Request 1 (top news):
  - Returned 15 items across Google News / Yahoo! / NYT with provenance.
  - Accuracy: Good source and item coverage.
- Request 2 (action-adventure movies):
  - Returned `capability_unavailable`.
  - Accuracy: truthful failure, but no requested listings.
- Request 3 (Jaffna Kool recipe):
  - Returned detailed markdown recipe.
  - Accuracy: useful, plausible answer.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation/phase-2/xdg/recurgent/recurgent.jsonl` (`17` entries)
- Solver-shape telemetry remains complete:
  - `solver_shape` present on all entries.
  - `solver_shape_complete=true` on all entries.
- Trace summary:
  - Calculator: 8 top-level calls, all logged `ok` (including solve, which returned an error payload inside success envelope).
  - Assistant: 3 top-level `ask` calls (`ok`, `capability_unavailable`, `ok`).
  - News flow delegated through `rss_feed_fetcher` and `rss_feed_parser`.
- Scorecard evidence:
  - Artifact version scorecard persisted (example: calculator `solve` artifact has one checksum entry with `calls=1, successes=1, failures=0`).
  - Registry-level version scorecards and coherence fields persisted for delegated tools (for example `rss_feed_fetcher`, `rss_feed_parser`).
- Diagnosis:
  - What went well:
    - Version-scoped scorecards and coherence metadata are being written without breaking existing metrics/tests.
    - Observational solver-shape and prior behavior surfaces are intact.
  - Needs improvement:
    - Calculator `solve` semantic quality is still unstable and can hide errors inside success outcomes.
    - Movie-listings request still lacks a tolerant fallback implementation path.

## Phase 3

### Changes

- Added promotion policy contract `solver_promotion_v1` with shadow-only lifecycle evaluation.
- Implemented shadow lifecycle state machine persisted per artifact version:
  - `candidate -> probation -> durable`
  - regression path to `degraded`
- Added lifecycle + decision ledger persistence on artifacts:
  - `artifact["lifecycle"]["versions"][checksum]`
  - `artifact["lifecycle"]["shadow_ledger"]["evaluations"]`
- Added observability fields for policy/lifecycle decisions:
  - `promotion_policy_version`
  - `lifecycle_state`
  - `lifecycle_decision`
  - `promotion_decision_rationale`
  - `promotion_shadow_mode`
  - `promotion_enforced`
- Added runtime config flags:
  - `solver_shape_capture_enabled`
  - `promotion_shadow_mode_enabled`
  - `promotion_enforcement_enabled`

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-3/xdg bundle exec rspec`
- Result: PASS
- Evidence: `tmp/phase-validation/phase-3/rspec.txt`
- Summary:
  - `241 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-3/xdg ruby examples/calculator.rb`
- Result: PARTIAL
- Evidence: `tmp/phase-validation/phase-3/calculator.txt`
- Output checks:
  - `add(3) => 8`
  - `multiply(4) => 0` (unexpected)
  - `sqrt(latest_result)` errored with execution failure
  - Remaining calls (`sqrt(144)`, `factorial`, `convert`, `solve`) succeeded
- Accuracy assessment:
  - Calculator chain is unstable in this run due multiply/sqrt regression.

#### Assistant example

- Command: `cd runtimes/ruby && printf ... | XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-3/xdg ruby examples/assistant.rb`
- Result: PARTIAL
- Evidence: `tmp/phase-validation/phase-3/assistant.txt`
- Request 1 (top news):
  - Returned large payload, but Google News parse failed (`parse_failed`) while Yahoo/NYT succeeded.
  - Accuracy: Partial; source completeness is degraded.
- Request 2 (action-adventure movies):
  - Returned `capability_unavailable`.
  - Accuracy: truthful failure, missing requested listings.
- Request 3 (Jaffna Kool recipe):
  - Returned structured recipe object.
  - Accuracy: useful and plausible.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation/phase-3/xdg/recurgent/recurgent.jsonl` (`15` entries)
- Lifecycle telemetry verification:
  - `lifecycle_state` present on all 15 entries.
  - Decision values observed: `continue_probation`, `hold`.
  - `promotion_shadow_mode=true` and `promotion_enforced=false` for all observed calls.
- Shadow lifecycle artifact evidence:
  - Assistant `ask` artifact stores 3 checksum versions with mixed states (`candidate` and `probation`) and 3 shadow evaluations.
  - Calculator `sqrt` artifact stores separate checksum versions with `candidate/hold` and `probation/continue_probation`.
- Diagnosis:
  - What went well:
    - Shadow engine is writing deterministic lifecycle/decision evidence without enforcing selector changes.
    - Log contract now exposes policy version and rationale for each call.
  - Needs improvement:
    - Runtime quality remains volatile on calculator and news parsing paths; shadow data correctly captures unstable candidates but product behavior still varies.
    - No promotions yet under v1 thresholds (expected with low observation windows).

## Phase 4

### Changes

- Added version payload storage under artifacts (`artifact["versions"][checksum]`) for deterministic fallback to prior versions.
- Implemented enforcement-aware persisted artifact selection (feature-flagged):
  - selection order: `durable` -> `probation` -> `candidate`
  - lifecycle-aware selection metadata surfaced in call state/log fields.
- Added kill-switch behavior via runtime config (`promotion_enforcement_enabled`).
- Added enforcement test coverage proving durable-over-probation selection when enforcement is enabled.

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-4/xdg bundle exec rspec`
- Result: PASS
- Evidence: `tmp/phase-validation/phase-4/rspec.txt`
- Summary:
  - `242 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-4/xdg ruby examples/calculator.rb`
- Result: PASS (for observed flow)
- Evidence: `tmp/phase-validation/phase-4/calculator.txt`
- Output checks:
  - `add(3) => 8`
  - `multiply(4) => 32`
  - `sqrt(32) => 5.656854249492381`
  - `sqrt(144) => 12.0`
  - `factorial(10) => 3628800`
  - `convert(100, celsius->fahrenheit) => 212.0`
  - `solve('2x + 5 = 17') => solution 6.0`
- Accuracy assessment: Correct for this run.

#### Assistant example

- Command: `cd runtimes/ruby && printf ... | XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-4/xdg ruby examples/assistant.rb`
- Result: PARTIAL
- Evidence: `tmp/phase-validation/phase-4/assistant.txt`
- Request 1 (top news):
  - Returned 10 headlines from Google + NYT; Yahoo branch failed with URI parsing error.
  - Accuracy: Partial source coverage only (requested 3 sources, returned 2 with explicit error).
- Request 2 (action-adventure movies):
  - Returned movie list with `retrieval_mode: "fixture"` provenance.
  - Accuracy: Structurally useful, but not real-time theater accuracy.
- Request 3 (Jaffna Kool recipe):
  - Returned detailed markdown recipe.
  - Accuracy: Useful and plausible.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation/phase-4/xdg/recurgent/recurgent.jsonl` (`13` entries)
- Lifecycle/decision evidence:
  - All logged top-level calls show lifecycle decisions (`continue_probation`) with `promotion_shadow_mode=true`.
  - Artifact selection metadata fields exist in schema but were empty this run (`artifact_hit=0`), so enforcement path did not trigger in examples.
- Enforcement correctness evidence:
  - Verified by passing spec: durable version selected over probation version when `promotion_enforcement_enabled=true`, and pre-policy behavior when disabled.
- Diagnosis:
  - What went well:
    - Enforcement machinery is implemented and test-verified with kill-switch support.
    - No regressions in full automated test suite.
  - Needs improvement:
    - Example runs still highly variable in delegated tool quality.
    - News aggregator robustness (Yahoo branch) and real-time movie listing capability need hardening.

## Phase 5

### Changes

- Propagated lifecycle/policy snapshots into registry metadata on tool usage updates.
- Extended known-tool ranking to prioritize lifecycle reliability:
  - durable > probation > candidate > degraded
  - degraded penalty in utility scoring.
- Extended `<known_tools>` prompt rendering with compact reliability/lifecycle hints:
  - `lifecycle: <state> (policy: <version>)`
  - `reliability: calls=..., success_rate=..., wrong_boundary=..., retries_exhausted=...`
  - `caution:` line for degraded tools.
- Added prompt-construction tests for lifecycle-priority ranking and rendered metadata hints.

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-5/xdg bundle exec rspec`
- Result: PASS
- Evidence: `tmp/phase-validation/phase-5/rspec.txt`
- Summary:
  - `243 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-5/xdg ruby examples/calculator.rb`
- Result: PASS
- Evidence: `tmp/phase-validation/phase-5/calculator.txt`
- Output checks:
  - `add(3) => 8`, `multiply(4) => 32`, `sqrt(32) => 5.656854249492381`
  - `sqrt(144) => 12.0`, `factorial(10) => 3628800`, `convert(...) => 212.0`
  - `solve('2x + 5 = 17') => 6.0`
- Accuracy assessment: Correct for this run.

#### Assistant example

- Command: `cd runtimes/ruby && printf ... | XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-5/xdg ruby examples/assistant.rb`
- Result: PARTIAL
- Evidence: `tmp/phase-validation/phase-5/assistant.txt`
- Request 1 (top news):
  - Returned all 3 sources with 5 sampled headlines each and provenance.
  - Accuracy: Good source coverage and structured output.
- Request 2 (action-adventure movies):
  - Returned `capability_unavailable`.
  - Accuracy: truthful failure, no real showtime listings.
- Request 3 (Jaffna Kool recipe):
  - Returned structured recipe/details.
  - Accuracy: useful and plausible.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation/phase-5/xdg/recurgent/recurgent.jsonl` (`14` entries)
- Runtime trace:
  - Roles observed: `calculator` (8), `rss_feed_reader` (3), assistant (3).
  - Assistant statuses: `ok`, `capability_unavailable`, `ok`.
- Prompt integration evidence:
  - Assistant debug `system_prompt` contains lifecycle/reliability lines:
    - `lifecycle: probation (policy: solver_promotion_v1)`
    - `reliability: calls=1, success_rate=1.0, wrong_boundary=0, retries_exhausted=0`
- Diagnosis:
  - What went well:
    - Lifecycle-aware known-tools rendering and ranking are active and test-covered.
    - Prompt footprint remained compact while adding reliability cues.
  - Needs improvement:
    - Movie-listings capability still unresolved in runtime tooling.
    - Lifecycle data in this run remained mostly `probation/candidate`, so durable preference could not be observed in real example flow.

## Phase 6

### Changes

- Added operations/governance documentation for lifecycle migration, tuning, rollback, and policy-version governance:
  - `docs/observability.md`
  - `docs/maintenance.md`
  - `docs/governance.md`
- Extended operator command surface in `bin/recurgent-tools`:
  - `scorecards <role> <method>`
  - `decisions <role> <method>`
  - `set-lifecycle <role> <method> <checksum> <state> [--reason ...] [--apply]`
- Added audited manual override persistence via `lifecycle.manual_overrides`.
- Added legacy lifecycle migration mode:
  - existing pre-lifecycle artifacts initialize with `legacy_compatibility_mode=true`
  - compatibility entries start in `probation` for policy re-qualification.

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-6/xdg bundle exec rspec`
- Result: PASS
- Evidence: `tmp/phase-validation/phase-6/rspec.txt`
- Summary:
  - `243 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-6/xdg ruby examples/calculator.rb`
- Result: PASS
- Evidence: `tmp/phase-validation/phase-6/calculator.txt`
- Output checks:
  - `add(3) => 8`, `multiply(4) => 32`, `sqrt(32) => 5.656854249492381`
  - `sqrt(144) => 12.0`, `factorial(10) => 3628800`
  - `convert(...) => { result: 212.0 }`
  - `solve('2x + 5 = 17') => 6.0`
- Accuracy assessment: Correct for this run.

#### Assistant example

- Command: `cd runtimes/ruby && printf ... | XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation/phase-6/xdg ruby examples/assistant.rb`
- Result: PARTIAL
- Evidence: `tmp/phase-validation/phase-6/assistant.txt`
- Request 1 (top news):
  - Returned all three requested sources with concrete headline lists and provenance.
  - Accuracy: Good source coverage.
- Request 2 (action-adventure movies):
  - Returned `capability_unavailable` ("Execution failed").
  - Accuracy: Failure acknowledged, but request not fulfilled.
- Request 3 (Jaffna Kool recipe):
  - Returned structured recipe payload.
  - Accuracy: useful and plausible.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation/phase-6/xdg/recurgent/recurgent.jsonl` (`15` entries)
- Trace summary:
  - Roles: `calculator` (8), assistant (3), `stable_finance_tool` (3), `movie_listings` (1).
  - Assistant statuses: `ok`, `capability_unavailable`, `ok`.
- Operator command verification:
  - `bin/recurgent-tools scorecards "personal assistant that remembers conversation history" "ask" --root <phase-6 tools root>` succeeded and returned version-scoped scorecards.
  - `bin/recurgent-tools decisions ... --limit 5` succeeded and returned shadow decision rationale entries.
  - Evidence files:
    - `tmp/phase-validation/phase-6/operator-scorecards.json`
    - `tmp/phase-validation/phase-6/operator-decisions.json`
- Diagnosis:
  - What went well:
    - Final lifecycle operations/governance surfaces are documented and executable.
    - Operator inspection tools return the expected scorecard/decision data.
  - Needs improvement:
    - Assistant movie-listings pathway remains unreliable and frequently unfulfilled.
    - Candidate-quality variability remains the dominant product risk despite improved policy/introspection controls.
