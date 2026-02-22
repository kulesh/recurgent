# ADR 0027 Phase 3 Validation

- Date: 2026-02-22
- Phase scope: G2 score consistency and deterministic scorer
- Commands:
  - `mise exec -- bundle exec rubocop`
  - `mise exec -- bundle exec rspec`
  - `mise exec -- env XDG_STATE_HOME=... ruby examples/calculator.rb`
  - `mise exec -- env XDG_STATE_HOME=... ruby examples/assistant.rb`
  - `mise exec -- ruby bin/recurgent-sim --pack ... --mode fixture`
  - `mise exec -- ruby bin/recurgent-sim --pack ... --mode replay` (twice)
- Artifacts:
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-3-rubocop.txt`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-3-rspec.txt`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-3-calculator.txt`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-3-calculator.jsonl`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-3-assistant.txt`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-3-assistant.jsonl`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-3-sim-fixture.json`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-3-sim-replay-1.json`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-3-sim-replay-2.json`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-3-sim-run-ledger.jsonl`

## Lint and Test Suite

- RuboCop: pass (`103 files`, `0 offenses`).
- RSpec: pass (`282 examples`, `0 failures`).

## Simulation Harness (Phase Feature Validation)

Observed scorer behavior:

- `scorer_version`: `simulation_scorer_v1`
- deterministic score vector emitted in ledger:
  - correctness: `0.7`
  - contract_adherence: `0.15`
  - repair_efficiency: `0.1`
  - reuse: `0.05`
  - overall: `1.0`
- replay run #1: `G2=advisory` (no prior comparable replay baseline)
- replay run #2: `G2=pass` (score vector matched prior replay baseline)

Diagnosis:

- Deterministic scoring and reproducibility checks are working as designed for class-1 deterministic packs.

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
- `history` -> method failed; script printed fallback history

### Accuracy Assessment

- `add_ok`: `true`
- `multiply_ok`: `true`
- `sqrt_latest_ok`: `true`
- `sqrt_144_ok`: `true`
- `factorial_ok`: `true`
- `convert_ok`: `true`
- `solve_ok`: `false`
- `history_method_ok`: `false`
- `overall_ok`: `partial`

### Trace Diagnosis

- Entries: `8`
- Error types: `guardrail_retry_exhausted` x2 (`solve`, `history`)
- Failure shape unchanged from prior phases: role-profile continuity retries still exhausted for `solve`/`history` paths.

## Assistant Run (`examples/assistant.rb` with required 3 prompts)

### Prompt 1: Top news from Google, Yahoo, NY Times

Observed:

- Top-level `ask` returned `guardrail_retry_exhausted` in this run (no news payload returned).

### Prompt 2: Action adventure movies in theaters

Observed:

- Returned boundary-honest `capability_unavailable`.

### Prompt 3: Jaffna Kool recipe

Observed:

- Returned detailed, concrete recipe with ingredients and instructions.

### Accuracy Assessment

- `news_success`: `false`
- `movies_capability_boundary_honest`: `true`
- `recipe_has_ingredients`: `true`
- `recipe_has_instructions`: `true`
- `overall_ok`: `mixed`

### Trace Diagnosis

- Entries: `6`
- Error types:
  - `guardrail_retry_exhausted` x1 (news ask)
  - `capability_unavailable` x1 (movies)
- Recipe path succeeded without delegated fetch failures in this run.

## Phase 3 Improvement Contract Check

Expected:

1. deterministic scorer emits diff-friendly score vectors.
2. same replay config yields reproducible score vectors.

Observed:

1. `score_vector` + `scorer_version` now emitted to run ledger.
2. replay #2 against same baseline produced `G2=pass` with exact score-vector match.
3. full suite remains green.

Phase conclusion:

- G2 scoring substrate is implemented and reproducibility checks are active.
- Runtime/example semantic instability remains orthogonal and continues to surface in mandatory trace runs.
