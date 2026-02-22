# ADR 0027 Phase 5 Validation

- Date: 2026-02-22
- Phase scope: G4 baseline-diff engine
- Commands:
  - `mise exec -- bundle exec rubocop`
  - `mise exec -- bundle exec rspec`
  - `mise exec -- env XDG_STATE_HOME=... ruby examples/calculator.rb`
  - `mise exec -- env XDG_STATE_HOME=... ruby examples/assistant.rb`
  - `mise exec -- ruby bin/recurgent-sim --pack ... --mode fixture` (run 1)
  - `mise exec -- ruby bin/recurgent-sim --pack ... --mode fixture` (run 2)
- Artifacts:
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-5-rubocop.txt`](logs/phase-5-rubocop.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-5-rspec.txt`](logs/phase-5-rspec.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-5-calculator.txt`](logs/phase-5-calculator.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-5-calculator.jsonl`](logs/phase-5-calculator.jsonl)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-5-assistant.txt`](logs/phase-5-assistant.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-5-assistant.jsonl`](logs/phase-5-assistant.jsonl)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-5-sim-run-1.json`](logs/phase-5-sim-run-1.json)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-5-sim-run-2.json`](logs/phase-5-sim-run-2.json)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-5-sim-run-ledger.jsonl`](logs/phase-5-sim-run-ledger.jsonl)

## Lint and Test Suite

- RuboCop: pass (`107 files`, `0 offenses`).
- RSpec: pass (`287 examples`, `0 failures`).

## Simulation Harness (Phase Feature Validation)

G4 baseline-diff validation results:

1. First fixture run produced `classification=no_baseline` and `G4=pass`.
2. Second fixture run produced `classification=unchanged` and `G4=pass`.
3. Diff report persisted to artifact path under `tmp/simulation/diffs/<run_id>.json`.

Diagnosis:

- Phase-5 objective achieved: baseline diff report generation is now guaranteed per run.
- Classification and suspected-cause fields are machine-readable and persisted in run ledger.

## Calculator Run (`examples/calculator.rb`)

### Observed Output

- `add(3)` -> `8.0`
- `multiply(4)` -> `32.0`
- `sqrt(latest_result)` -> `5.656854249492381`
- `runtime_context[:memory] || runtime_context[:value]` -> `5.656854249492381`
- `sqrt(144)` -> `5.656854249492381` (incorrect)
- `factorial(10)` -> `3628800`
- `convert(100, celsius->fahrenheit)` -> `212.0`
- `solve('2x + 5 = 17')` -> `6.0`
- `history` -> method failed (`guardrail_retry_exhausted`), script fallback printed history entries

### Accuracy Assessment

- `add_ok`: `true`
- `multiply_ok`: `true`
- `sqrt_latest_ok`: `true`
- `sqrt_144_ok`: `false`
- `factorial_ok`: `true`
- `convert_ok`: `true`
- `solve_ok`: `true`
- `history_method_ok`: `false`
- `overall_ok`: `false`

### Trace Diagnosis

- Entries: `8`
- Error types: `guardrail_retry_exhausted` x1 (`history`)
- Improvement vs prior phase: `solve` recovered to correct output (`6.0`), but deterministic `sqrt(144)` behavior is still wrong and `history` remains unstable.

## Assistant Run (`examples/assistant.rb` with required 3 prompts)

### Observed

1. News prompt succeeded with structured source output and top items from Google News, Yahoo! News, and NY Times.
2. Movies prompt returned boundary failure (`capability_not_available`) due to no theater/showtime API capability.
3. Recipe prompt failed with `unsupported_capability` from `recipe_search` boundary constraints.

### Accuracy Assessment

- `news_success`: `true` (content quality acceptable; source links returned)
- `movies_boundary_or_result`: `true` (honest boundary response)
- `recipe_success`: `false` (capability gap unresolved)
- `overall_ok`: `false`

### Trace Diagnosis

- Entries: `3`
- Status profile: one successful content response + two typed boundary failures.
- Diagnostics quality improved: errors are explicit and typed, but capability coverage remains insufficient for recipe use case.

## Phase 5 Improvement Contract Check

Expected:

1. every class-1 run emits a baseline diff report,
2. diff classification is actionable (`improved/regressed/unchanged/no_baseline`).

Observed:

1. both phase simulation runs emitted `baseline_diff_report`,
2. first run produced `no_baseline`, second run produced `unchanged`,
3. reports include gate deltas, noise flag, and suspected causes.

Phase conclusion:

- G4 implementation is complete and validated.
- Example semantic stability remains mixed and is captured in this phase record.
