# ADR 0027 Phase 1 Validation

- Date: 2026-02-22
- Phase scope: G0 scenario contracts and class-1 packs
- Commands:
  - `mise exec -- bundle exec rubocop`
  - `mise exec -- bundle exec rspec`
  - `mise exec -- env XDG_STATE_HOME=... ruby examples/calculator.rb`
  - `mise exec -- env XDG_STATE_HOME=... ruby examples/assistant.rb`
- Artifacts:
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-1-rubocop.txt`](logs/phase-1-rubocop.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-1-rspec.txt`](logs/phase-1-rspec.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-1-calculator.txt`](logs/phase-1-calculator.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-1-calculator.jsonl`](logs/phase-1-calculator.jsonl)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-1-assistant.txt`](logs/phase-1-assistant.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-1-assistant.jsonl`](logs/phase-1-assistant.jsonl)

## Lint and Test Suite

- RuboCop: pass (`95 files`, `0 offenses`).
- RSpec: pass (`278 examples`, `0 failures`).

## Calculator Run (`examples/calculator.rb`)

### Observed Output

- `add(3)` -> `8.0`
- `multiply(4)` -> `32.0`
- `sqrt(latest_result)` -> `5.656854249492381`
- `runtime_context[:memory] || runtime_context[:value]` -> `5.656854249492381`
- `sqrt(144)` -> `12.0`
- `factorial(10)` -> `3628800`
- `convert(100, celsius->fahrenheit)` -> `212.0`
- `solve('2x + 5 = 17')` -> `6.0`
- `history` -> method failed (`guardrail_retry_exhausted`), printed fallback conversation history from script

### Accuracy Assessment

- `add_ok`: `true`
- `multiply_ok`: `true`
- `sqrt_latest_ok`: `true`
- `runtime_context_ok`: `false` (script checks for `32`; runtime value reflects later `sqrt` overwrite)
- `sqrt_144_ok`: `true`
- `factorial_ok`: `true`
- `convert_ok`: `true`
- `solve_ok`: `true`
- `history_method_ok`: `false`
- `overall_ok`: `partial`

### Trace Diagnosis

- Entries: `8`
- Method status:
  - `ok`: add, multiply, sqrt (x2), factorial, convert, solve
  - `error`: history
- Error types:
  - `guardrail_retry_exhausted` x1

Root cause of remaining failure:

- `history` generated a return hash and state references that diverged from role-profile continuity expectations (`state key diverged`, expected shared `memory` slot coherence), exhausted retry budget.
- `solve` improved in this run: code returned numeric `Outcome.ok(x)` and aligned with arithmetic shape.

## Assistant Run (`examples/assistant.rb` with required 3 prompts)

### Prompt 1: Top news from Google News, Yahoo, NY Times

Observed:

- Returned Yahoo and NY Times lists.
- Google feed parse path failed (`feed_string is empty or nil`), represented as source-level error entry.

Accuracy:

- `news_has_google_items`: `false`
- `news_has_yahoo_items`: `true`
- `news_has_nyt_items`: `true`
- `news_overall_ok`: `partial`

### Prompt 2: Action adventure movies in theaters

Observed:

- Returned `capability_unavailable` boundary message.

Accuracy:

- `movies_capability_boundary_honest`: `true`
- `movies_listing_success`: `false`

### Prompt 3: Good recipe for Jaffna Kool

Observed:

- Returned structured recipe payload (ingredients + instructions + notes).

Accuracy:

- `recipe_mentions_jaffna`: `true`
- `recipe_has_ingredients`: `true`
- `recipe_has_instructions`: `true`
- `recipe_overall_ok`: `true`

### Trace Diagnosis

- Entries: `12`
- Method status:
  - `ask`: ok x2, error x1
  - `fetch_url`: ok x3
  - `fetch_feed`: ok x3
  - `parse`: ok x2, error x1
- Error types:
  - `capability_unavailable` x1 (movies)
  - `invalid_input` x1 (Google parse path)

## Phase 1 Improvement Contract Check

Expected:

1. At least two class-1 machine-checkable packs.
2. Oracle/scoring contracts validated in test pipeline.

Observed:

1. Added `calculator-core-v1` and `calculator-edge-v1` under [`specs/contract/v1/simulation/scenario-packs/`](../../../../specs/contract/v1/simulation/scenario-packs).
2. Added schema and loader/validator with tests:
   - [`specs/contract/v1/simulation-scenario-pack.schema.json`](../../../../specs/contract/v1/simulation-scenario-pack.schema.json)
   - [`runtimes/ruby/lib/recurgent/simulation_pack_contract.rb`](../../../../runtimes/ruby/lib/recurgent/simulation_pack_contract.rb)
   - [`runtimes/ruby/lib/recurgent/simulation_scenario_pack.rb`](../../../../runtimes/ruby/lib/recurgent/simulation_scenario_pack.rb)
   - [`runtimes/ruby/spec/contract/simulation_scenario_pack_spec.rb`](../../../../runtimes/ruby/spec/contract/simulation_scenario_pack_spec.rb)
3. Full suite remains green.

Phase conclusion:

- Phase 1 goals are met for G0 contract hardening.
- Runtime semantic instability persists in example flows (`history`, live-source news variability), as expected for this phase.
