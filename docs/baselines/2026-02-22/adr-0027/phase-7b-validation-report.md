# ADR-0027 Phase 7b Validation Report

Date (UTC): 2026-02-22

## Scope

Phase 7b objective: add class-2+ advisory simulation packs (assistant + debate), run them in nightly flow as non-gating, and publish advisory status reporting.

## What Was Implemented

1. Added class-2+ scenario packs:
   - [`specs/contract/v1/simulation/scenario-packs/assistant-continuity-v1.yaml`](../../../../specs/contract/v1/simulation/scenario-packs/assistant-continuity-v1.yaml)
   - [`specs/contract/v1/simulation/scenario-packs/debate-orchestration-v1.yaml`](../../../../specs/contract/v1/simulation/scenario-packs/debate-orchestration-v1.yaml)
2. Extended oracle evaluator with advisory kinds:
   - `assistant_followup_case`
   - `provenance_envelope_case`
   - `typed_error_boundary_case`
   - `debate_orchestration_case`
3. Added advisory aggregation/reporting:
   - [`runtimes/ruby/lib/recurgent/simulation_advisory_status.rb`](../../../../runtimes/ruby/lib/recurgent/simulation_advisory_status.rb)
   - [`runtimes/ruby/bin/recurgent-sim-advisory-report`](../../../../runtimes/ruby/bin/recurgent-sim-advisory-report)
   - nightly workflow now runs advisory packs and writes advisory JSON + markdown artifact.
4. Added tests for new surfaces:
   - [`runtimes/ruby/spec/simulation_calculator_oracle_spec.rb`](../../../../runtimes/ruby/spec/simulation_calculator_oracle_spec.rb)
   - [`runtimes/ruby/spec/simulation_advisory_status_spec.rb`](../../../../runtimes/ruby/spec/simulation_advisory_status_spec.rb)
   - updated contract pack spec for class-1 + class-2+ packs.

## Required Validation Runs

### 1) Entire test suite

- RuboCop: pass (`115 files inspected, no offenses`).
- RSpec: pass (`298 examples, 0 failures`).

Artifacts:
- [`docs/baselines/2026-02-22/adr-0027/logs/phase-7b-rubocop.txt`](logs/phase-7b-rubocop.txt)
- [`docs/baselines/2026-02-22/adr-0027/logs/phase-7b-rspec.txt`](logs/phase-7b-rspec.txt)

### 2) Calculator example

Observed top-level outcomes:
- `add`: ok (`8.0`)
- `multiply`: ok (`32.0`)
- `sqrt(latest_result)`: ok (`5.656854249492381`)
- `sqrt(144)`: **incorrect** (`5.656854249492381`, expected `12.0`)
- `factorial(10)`: ok (`3628800`)
- `convert(100, celsius->fahrenheit)`: ok (`212.0`)
- `solve`: error (`guardrail_retry_exhausted`)
- `history`: error (`guardrail_retry_exhausted`)

Trace diagnosis:
- `solve` failed with `role_profile_continuity_violation` (`return_shape_family_drift` + state-key correction pressure).
- `history` failed with `role_profile_continuity_violation` (`shared_state_slot_drift`).

Artifacts:
- [`docs/baselines/2026-02-22/adr-0027/logs/phase-7b-calculator.txt`](logs/phase-7b-calculator.txt)
- [`docs/baselines/2026-02-22/adr-0027/logs/phase-7b-calculator.jsonl`](logs/phase-7b-calculator.jsonl)

### 3) Personal assistant (3 required prompts)

Prompts:
1. top news (Google/Yahoo/NYT)
2. action-adventure movies in theaters
3. recipe for Jaffna Kool

Observed outcomes:
- Prompt 1: error `guardrail_retry_exhausted` (no news payload returned).
- Prompt 2: typed `capability_unavailable` (expected boundary honesty).
- Prompt 3: success with structured Jaffna Kool recipe payload.

Trace diagnosis for prompt 1 failure:
- top-level role-profile continuity retries exhausted (`conversation_history` key continuity corrections).
- delegated failures included:
  - `rss_parser.parse_feed` -> `invalid_input` (empty feed content)
  - `rss_parser.parse` -> `invalid_input` (empty XML)

Artifacts:
- [`docs/baselines/2026-02-22/adr-0027/logs/phase-7b-assistant.txt`](logs/phase-7b-assistant.txt)
- [`docs/baselines/2026-02-22/adr-0027/logs/phase-7b-assistant.jsonl`](logs/phase-7b-assistant.jsonl)

## 7b-Specific Advisory Pack Validation

Local nightly-equivalent advisory pack run succeeded and generated report artifacts:
- Advisory markdown: [`docs/reports/simulation-advisory-status-2026-02-22.md`](../../../reports/simulation-advisory-status-2026-02-22.md)
- Advisory analysis JSON: [`docs/baselines/2026-02-22/adr-0027/logs/phase-7b-advisory-analysis.json`](logs/phase-7b-advisory-analysis.json)
- Advisory status JSON: [`docs/baselines/2026-02-22/adr-0027/logs/phase-7b-advisory-status.json`](logs/phase-7b-advisory-status.json)
- Replay evidence:
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-7b-assistant-pack-replay-2.json`](logs/phase-7b-assistant-pack-replay-2.json)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-7b-debate-pack-replay-2.json`](logs/phase-7b-debate-pack-replay-2.json)

Observed advisory result snapshot:
- Pack count: 2 (`assistant-continuity-v1`, `debate-orchestration-v1`)
- Replay runs analyzed: 4
- Both packs latest gate snapshots: `G0..G5 = pass`
- Failure signatures are advisory startup artifacts (`G2=advisory`, `G3=advisory`, `baseline_diff:no_baseline`) on first replay only.

## Phase-7a Window Progress (carry-forward context)

After additional runs (`r9..r20`):
- consecutive qualifying runs: `20` (met)
- seeds: `5` (met)
- sessions: `20` (met)
- distinct UTC days: `1` (**not met**, requires `3`)
- `window_met=false`

## Expected vs Observed (Phase 7b)

Expected:
1. class-2+ packs exist and run under nightly only.
2. advisory results are captured without affecting class-1 merge gating.
3. advisory status report is generated from ledger evidence.

Observed:
1. Achieved.
2. Achieved.
3. Achieved.

Not improved by 7b (as expected, outside 7b scope):
1. calculator semantic stability (`sqrt(144)` regression in this run; `solve/history` continuity failures).
2. assistant first prompt reliability (still susceptible to guardrail/continuity + delegated parser instability).

## Conclusion

Phase 7b implementation is complete from infrastructure perspective:
- advisory packs are now part of simulation surface,
- nightly advisory execution/reporting is wired,
- advisory remains non-gating.

Operational readiness to promote class-2 beyond advisory remains blocked by class-1 observation window day-count criterion and unresolved semantic instability in examples.
