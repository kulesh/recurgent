# ADR 0027 Phase 4 Validation

- Date: 2026-02-22
- Phase scope: G3 trace-integrity gate (schema validation)
- Commands:
  - `mise exec -- bundle exec rubocop`
  - `mise exec -- bundle exec rspec`
  - `mise exec -- env XDG_STATE_HOME=... ruby examples/calculator.rb`
  - `mise exec -- env XDG_STATE_HOME=... ruby examples/assistant.rb`
  - `mise exec -- ruby bin/recurgent-sim --pack ... --trace-log <valid>`
  - `mise exec -- ruby bin/recurgent-sim --pack ... --trace-log <invalid>`
- Artifacts:
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-4-rubocop.txt`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-4-rspec.txt`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-4-calculator.txt`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-4-calculator.jsonl`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-4-assistant.txt`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-4-assistant.jsonl`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-4-sim-trace-pass.json`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-4-sim-trace-fail.json`
  - `docs/baselines/2026-02-22/adr-0027/logs/phase-4-sim-run-ledger.jsonl`

## Lint and Test Suite

- RuboCop: pass (`105 files`, `0 offenses`).
- RSpec: pass (`285 examples`, `0 failures`).

## Simulation Harness (Phase Feature Validation)

G3 validation results:

1. Valid trace stream (`phase-4-calculator.jsonl`) -> `G3=pass`.
2. Intentionally invalid stream (`{"bad":"entry"}`) -> `G3=fail`.

Failure diagnostics include first invalid location:

- field path: `$`
- entry index: `0`
- reason: missing required fields (`timestamp`, `role`, `model`, `method`, `args`, `kwargs`, `code`, `duration_ms`, `generation_attempt`)

Diagnosis:

- Phase-4 objective achieved: trace-schema gate is now executable with explicit failure localization.

## Calculator Run (`examples/calculator.rb`)

### Observed Output

- `add(3)` -> `8.0`
- `multiply(4)` -> `32.0`
- `sqrt(latest_result)` -> `5.656854249492381`
- `runtime_context[:memory] || runtime_context[:value]` -> `5.656854249492381`
- `sqrt(144)` -> `5.656854249492381` (incorrect)
- `factorial(10)` -> `3628800`
- `convert(100, celsius->fahrenheit)` -> `212.0`
- `solve('2x + 5 = 17')` -> `[guardrail_retry_exhausted]`
- `history` -> method failed (`guardrail_retry_exhausted`), script fallback printed history array

### Accuracy Assessment

- `add_ok`: `true`
- `multiply_ok`: `true`
- `sqrt_latest_ok`: `true`
- `sqrt_144_ok`: `false`
- `factorial_ok`: `true`
- `convert_ok`: `true`
- `solve_ok`: `false`
- `history_method_ok`: `false`
- `overall_ok`: `false`

### Trace Diagnosis

- Entries: `8`
- Error types: `guardrail_retry_exhausted` x2 (`solve`, `history`)
- Regression pattern persists: continuity guard exhaustion in `solve`/`history`; state/shape divergence remains unresolved.

## Assistant Run (`examples/assistant.rb` with required 3 prompts)

### Observed

All three prompts returned the same top-level error:

- `[non_serializable_result] context contains non-JSON-compatible values`

### Accuracy Assessment

- `news_success`: `false`
- `movies_boundary_or_result`: `false`
- `recipe_success`: `false`
- `overall_ok`: `false`

### Trace Diagnosis

- Entries: `3`
- Method status: `ask:error` x3
- Error type: `non_serializable_result` x3

Diagnosis:

- This run hit a context-serialization failure that blocks all assistant turns in session scope.
- Failure is orthogonal to the simulation-trace gate implementation; it is a runtime/context hygiene issue exposed by mandatory phase traces.

## Phase 4 Improvement Contract Check

Expected:

1. simulation runner enforces trace schema validity.
2. failure output pinpoints first invalid entry/field.

Observed:

1. `G3` now evaluates to `pass`/`fail` based on trace-schema validation.
2. diagnostics include exact index + field path + reason.
3. full suite remains green.

Phase conclusion:

- G3 enforcement is implemented and validated.
- Runtime semantic instability in examples remains and is captured in this phase’s trace record.
