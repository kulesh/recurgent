# ADR 0027 Phase 6 Validation

- Date: 2026-02-22
- Phase scope: G5 CI/nightly operationalization
- Commands:
  - `mise exec -- bundle exec rubocop`
  - `mise exec -- bundle exec rspec`
  - `mise exec -- env XDG_STATE_HOME=... ruby examples/calculator.rb`
  - `mise exec -- env XDG_STATE_HOME=... ruby examples/assistant.rb`
  - `mise exec -- ruby bin/recurgent-sim --operational-mode ci` (fixture + replay x2)
  - `mise exec -- ruby bin/recurgent-sim --operational-mode nightly --seeds ...`
- Artifacts:
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-rubocop.txt`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-rspec.txt`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-calculator.txt`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-calculator.jsonl`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-assistant.txt`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-assistant.jsonl`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-sim-ci-core-fixture.json`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-sim-ci-core-replay-1.json`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-sim-ci-core-replay-2.json`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-sim-ci-edge-fixture.json`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-sim-ci-edge-replay-1.json`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-sim-ci-edge-replay-2.json`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-sim-nightly-fixture.json`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-sim-nightly-replay-1.json`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-sim-nightly-replay-2.json`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-sim-run-ledger.jsonl`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-6-sim-nightly-trend-report.json`

## Lint and Test Suite

- RuboCop: pass (`107 files`, `0 offenses`).
- RSpec: pass (`290 examples`, `0 failures`).

## Simulation Harness (Phase Feature Validation)

### G5 CI Operationalization

`phase-6-sim-ci-core-replay-2.json` and `phase-6-sim-ci-edge-replay-2.json` gate status:

- `G0=pass`
- `G1=pass`
- `G2=pass`
- `G3=pass`
- `G4=pass`
- `G5=pass`

`G5` message: `ci readiness gate executed`.

### Nightly Operationalization (expanded seed matrix)

Nightly-mode local run with seed override (`10` seeds) and matching fixture warmup produced:

- `G1=pass`
- `G2=pass`
- `G5=pass` with nightly trend-report path bound
- `G4=pass` with `classification=improved`

## Calculator Run (`examples/calculator.rb`)

### Observed Output

- `add(3)` -> `8.0`
- `multiply(4)` -> `32.0`
- `sqrt(latest_result)` -> `5.656854249492381`
- `runtime_context[:memory] || runtime_context[:value]` -> `5.656854249492381`
- `sqrt(144)` -> `12.0`
- `factorial(10)` -> `3628800`
- `convert(100, celsius->fahrenheit)` -> `212.0`
- `solve('2x + 5 = 17')` -> `[guardrail_retry_exhausted]`
- `history` -> method failed (`guardrail_retry_exhausted`), script fallback printed history entries

### Accuracy Assessment

- `add_ok`: `true`
- `multiply_ok`: `true`
- `sqrt_latest_ok`: `true`
- `sqrt_144_ok`: `true`
- `factorial_ok`: `true`
- `convert_ok`: `true`
- `solve_ok`: `false`
- `history_method_ok`: `false`
- `overall_ok`: `false`

### Trace Diagnosis

- Entries: `8`
- Error types: `guardrail_retry_exhausted` x2 (`solve`, `history`)
- Improvement observed: deterministic `sqrt(144)` is correct in this phase run.
- Remaining gap: `solve` and `history` continue to exhaust guardrail retries.

## Assistant Run (`examples/assistant.rb` with required 3 prompts)

### Observed

1. News prompt returned structured output; Google and NY Times succeeded, Yahoo feed returned `403`.
2. Movies prompt returned typed boundary failure: `capability_unavailable`.
3. Recipe prompt returned typed boundary failure: `capability_unavailable`.

### Accuracy Assessment

- `news_success`: `partial` (2/3 requested sources; Yahoo failed with `403`)
- `movies_boundary_or_result`: `true` (honest capability boundary)
- `recipe_success`: `false`
- `overall_ok`: `partial`

### Trace Diagnosis

- Entries: `7` total (`depth 0`: 3, `depth 1`: 4).
- Top-level `ask` outcomes:
  1. `ok`
  2. `error(capability_unavailable)`
  3. `error(capability_unavailable)`
- Delegation path in this run used `rss_feed_parser` for news; movie and recipe requests exited at boundary checks.

## Phase 6 Improvement Contract Check

Expected:

1. CI gate exists and can evaluate class-1 readiness gates.
2. Nightly workflow exists with expanded seed matrix and trend artifact publication.
3. Release/checklist docs include readiness-gate requirements.

Observed:

1. Added CI workflow: `.github/workflows/simulation-readiness-ci.yml` with per-pack gate evaluation and summary/artifact publishing.
2. Added nightly workflow: `.github/workflows/simulation-readiness-nightly.yml` with expanded-seed runs and trend report generation.
3. Runner/CLI now support `operational_mode` and nightly report path; `G5` is no longer always `not_applicable`.
4. Release/checklist/docs updated to include simulation readiness operational requirements.

Phase conclusion:

- G5 operationalization is implemented end-to-end.
- Class-1 readiness workflow wiring is complete; semantic instability in examples remains measurable and explicit in trace records.
