# ADR-0027 Phase 7 Validation Report

Date (UTC): 2026-02-22

## Scope

This report covers Phase 7a implementation and validation after introducing:
- stabilization-window analysis (`SimulationStabilizationWindow`),
- window run/status CLIs,
- qualifying-run bootstrap behavior for `G2` reproducibility,
- runbook alignment to `ci` qualifying mode.

## Commands Executed

1. Full lint: `cd runtimes/ruby && mise exec -- bundle exec rubocop`
2. Full test suite: `cd runtimes/ruby && mise exec -- bundle exec rspec`
3. Calculator example: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=... ruby examples/calculator.rb`
4. Assistant example with required prompts:
   - `What's the top news items in Google News, Yahoo! News, and NY Times`
   - `What's are the action adventure movies playing in theaters`
   - `What's a good recipe for Jaffna Kool`
5. Phase 7a window bundles (8 runs) + status:
   - `bin/recurgent-sim-window-run`
   - `bin/recurgent-sim-window-status`

## Artifact Index

- RuboCop: [`docs/baselines/2026-02-22/adr-0027/logs/phase-7-rubocop.txt`](logs/phase-7-rubocop.txt)
- RSpec: [`docs/baselines/2026-02-22/adr-0027/logs/phase-7-rspec.txt`](logs/phase-7-rspec.txt)
- Calculator stdout: [`docs/baselines/2026-02-22/adr-0027/logs/phase-7-calculator.txt`](logs/phase-7-calculator.txt)
- Calculator trace: [`docs/baselines/2026-02-22/adr-0027/logs/phase-7-calculator.jsonl`](logs/phase-7-calculator.jsonl)
- Assistant stdout: [`docs/baselines/2026-02-22/adr-0027/logs/phase-7-assistant.txt`](logs/phase-7-assistant.txt)
- Assistant trace: [`docs/baselines/2026-02-22/adr-0027/logs/phase-7-assistant.jsonl`](logs/phase-7-assistant.jsonl)
- Window runs: [`docs/baselines/2026-02-22/adr-0027/logs/phase-7a-window-run-1.json`](logs/phase-7a-window-run-1.json) .. `phase-7a-window-run-8.json`
- Window status: [`docs/baselines/2026-02-22/adr-0027/logs/phase-7a-window-status.json`](logs/phase-7a-window-status.json)
- Decision record: [`docs/reports/simulation-readiness-decision-2026-02-22.md`](../../../reports/simulation-readiness-decision-2026-02-22.md)

## Validation Results

### 1) Entire test suite

- RuboCop: pass (`111 files inspected, no offenses`).
- RSpec: pass (`293 examples, 0 failures`).

Assessment: expected behavior achieved.

### 2) Calculator run (examples/calculator.rb)

Observed top-level calls (from `phase-7-calculator.jsonl`):
- `add`: ok (`8.0`)
- `multiply`: ok (`32.0`)
- `sqrt(32.0)`: ok (`5.656854249492381`)
- `sqrt(144)`: ok (`12.0`)
- `factorial(10)`: ok (`3628800`)
- `convert(100, celsius->fahrenheit)`: ok (`212.0`)
- `solve('2x + 5 = 17')`: ok (`6.0`)
- `history`: error (`guardrail_retry_exhausted`)

Accuracy check:
- Arithmetic outputs are correct.
- `solve` output is correct for equation `2x + 5 = 17`.
- `history` remains incorrect due guardrail exhaustion.

Root-cause details for `history` failure:
- `guardrail_violation_subtype`: `role_profile_continuity_violation`
- `role_profile_violation_types`: `shared_state_slot_drift`
- Correction hint repeatedly requested alignment to `memory` key.
- Retry attempts exhausted after 2 validation retries.

Diagnosis:
- Core calculator semantics improved substantially (7/8 top-level calls successful).
- Remaining failure is profile coordination on `history` path, not arithmetic correctness.
- This aligns with expected continuity-pressure behavior: reliability gates can pass while example semantics still require method-level stabilization.

### 3) Assistant run (required 3 prompts)

Observed top-level calls (from `phase-7-assistant.jsonl`):
- Prompt 1 (news): `ok`, long duration (`~227s`), partial result.
- Prompt 2 (movies): `capability_unavailable`.
- Prompt 3 (recipe): `capability_unavailable`.

Prompt-by-prompt assessment:

1. News prompt:
- Returned only NYTimes content (`sources_returned=1`), with explicit errors for:
  - Google News: `non_serializable_result`
  - Yahoo! News: `non_serializable_result`
- Provenance present for returned source.
- Accuracy: partially correct (NYT headlines valid), incomplete against user request (Google + Yahoo missing).

2. Movies prompt:
- Returned typed `capability_unavailable` with concrete reason (no theater-listing API/runtime capability).
- Accuracy: contract-honest and expected under current capability boundary.

3. Recipe prompt:
- Returned typed `capability_unavailable` in this run.
- Accuracy: boundary-honest, but lower utility than earlier sessions where knowledge-base recipe responses were produced.

Delegated-failure diagnostics (depth>0):
- `rss_feed_reader.fetch_rss_feed`: `outcome_repair_retry_exhausted` (multiple times)
- `rss_feed_reader.fetch_rss_feed`: `contract_violation` (`type_mismatch`)
- `rss_feed_fetcher.fetch_feed`: `non_serializable_result` (multiple times)

Diagnosis:
- Delegation repair lanes are active and transparent, but feed-tool implementations remain unstable.
- Primary degradation driver is delegated tool output contract/serializability instability, not top-level error normalization.

## Phase 7a Window Status

From `phase-7a-window-status.json` (post-bootstrap implementation):
- `session_count`: 8
- `qualifying_session_count`: 8
- `trailing_consecutive_qualifying`: 8
- `distinct_seed_count`: 5
- `distinct_day_count`: 1
- `window_met`: false
- `reset_events`: none

Interpretation:
- Qualifying logic is now stable (8/8 qualifying in this capture).
- Readiness remains correctly blocked by observation-window policy (`20 runs` and `3 days` minimum unmet).

## Expected vs Observed Improvement

### Expected improvements for Phase 7a
- Window evidence should become machine-auditable and deterministic.
- Initial false reset from first-run `G2` advisory should be eliminated.
- Class-1 readiness should remain blocked until observation-window thresholds are met.

### Observed
- Achieved:
  - Window tooling works and emits decision artifacts.
  - `G2` bootstrap removed first-run reset in final capture (`reset_events=[]`).
  - Policy gate correctly remains `window_met=false` with 1/3 required days.
- Not achieved (outside direct Phase 7a mechanics but visible in phase traces):
  - Assistant semantic reliability for multi-source news remains unstable.
  - Calculator `history` method still violates role-profile continuity.

## What worked well

- Gate computation and ledger aggregation are clear, reproducible, and diagnosable.
- CI-qualifying mode alignment removed ambiguity in pass/fail semantics.
- Calculator core operations (add/multiply/sqrt/factorial/convert/solve) were accurate in final run.

## What needs improvement next

1. Calculator `history` continuity repair:
- Enforce or guide `history` method state-key behavior to satisfy `shared_state_slot` coordination.

2. Assistant news tool hardening:
- Eliminate non-serializable delegated outputs.
- Enforce delegation contract shape (`deliverable` type) before returning to parent.

3. Assistant utility fallback:
- For recipe requests, prefer deterministic knowledge-base response when web capability is unavailable, instead of immediate `capability_unavailable`.

## Readiness conclusion

- Phase 7a infrastructure: implemented and validated.
- Class-1 stability claim: not yet allowed by policy (insufficient run count/day spread).
- Advisory expansion can proceed only as non-gating until window criteria are fully satisfied.
