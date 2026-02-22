# ADR 0027 Phase 2 Validation

- Date: 2026-02-22
- Phase scope: G1 replayability and fixture pipeline
- Commands:
  - `mise exec -- bundle exec rubocop`
  - `mise exec -- bundle exec rspec`
  - `mise exec -- env XDG_STATE_HOME=... ruby examples/calculator.rb`
  - `mise exec -- env XDG_STATE_HOME=... ruby examples/assistant.rb`
  - `mise exec -- ruby bin/recurgent-sim --pack ... --mode fixture`
  - `mise exec -- ruby bin/recurgent-sim --pack ... --mode replay`
- Artifacts:
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-2-rubocop.txt`](logs/phase-2-rubocop.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-2-rspec.txt`](logs/phase-2-rspec.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-2-calculator.txt`](logs/phase-2-calculator.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-2-calculator.jsonl`](logs/phase-2-calculator.jsonl)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-2-assistant.txt`](logs/phase-2-assistant.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-2-assistant.jsonl`](logs/phase-2-assistant.jsonl)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-2-sim-fixture.json`](logs/phase-2-sim-fixture.json)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-2-sim-replay.json`](logs/phase-2-sim-replay.json)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-2-sim-run-ledger.jsonl`](logs/phase-2-sim-run-ledger.jsonl)

## Lint and Test Suite

- RuboCop: pass (`101 files`, `0 offenses`).
- RSpec: pass (`281 examples`, `0 failures`).

## Simulation Harness (Phase Feature Validation)

Observed:

- Fixture run (`calculator-core-v1`) completed and wrote fixture artifacts.
- Replay run over same pack/checksum/seeds produced `replay stability = 1.0` and `G1=status=pass`.
- Run ledger entries are emitted with required schema fields (`run_id`, `commit_sha`, `scenario_pack_id`, `seed`, `mode`, `gates`).

Diagnosis:

- Phase-2 goal achieved for deterministic fixture/replay flow and run-ledger integration in class-1 deterministic packs.

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
- `history` -> fallback printed because method errored (`guardrail_retry_exhausted`)

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
- `solve` violated arithmetic return-shape continuity by returning structured hash instead of numeric sibling shape.
- `history` violated state-key continuity expectations and exhausted retries.

## Assistant Run (`examples/assistant.rb` with required 3 prompts)

### Prompt 1: Top news from Google, Yahoo, NY Times

Observed:

- Returned Yahoo and NYTimes items; Google missing.
- Included provenance for successful sources.
- Trace includes upstream fetch repair exhaustion (`outcome_repair_retry_exhausted`) on one delegated feed path, but top-level still returned partial success.

Accuracy:

- `news_has_google_items`: `false`
- `news_has_yahoo_items`: `true`
- `news_has_nyt_items`: `true`
- `news_overall_ok`: `partial`

### Prompt 2: Action adventure movies in theaters

Observed:

- Returned boundary-honest `capability_unavailable`.

Accuracy:

- `movies_capability_boundary_honest`: `true`
- `movies_listing_success`: `false`

### Prompt 3: Jaffna Kool recipe

Observed:

- Returned `low_utility` in this run due delegated `web_searcher` misuse (`ok?`/`value` called as dynamic methods, leading to missing-parameter + low-utility path).

Accuracy:

- `recipe_mentions_jaffna`: `false` (terminal response was low-utility error)
- `recipe_has_ingredients`: `false`
- `recipe_has_instructions`: `false`
- `recipe_overall_ok`: `false`

### Trace Diagnosis

- Entries: `9`
- Method status:
  - `ask`: ok x1, error x2
  - delegated methods include `fetch_news`, `fetch_feed`, and invalid delegated `ok?` / `value` calls
- Error types:
  - `capability_unavailable` x1
  - `low_utility` x2
  - `missing_parameter` x1
  - `outcome_repair_retry_exhausted` x1

## Phase 2 Improvement Contract Check

Expected:

1. Seed-locked deterministic replay pipeline exists.
2. Fixture/replay modes are separated and ledgered.

Observed:

1. Added deterministic runner + fixture store + run ledger + CLI (`bin/recurgent-sim`).
2. Replay over fixture achieved exact match (`1.0` stability) in class-1 pack execution.
3. Gate statuses now include `G0` and `G1` in emitted ledger entries; remaining gates remain `not_applicable` at this phase.

Phase conclusion:

- G1 infrastructure is functioning for deterministic class-1 packs.
- Example/runtime semantics remain noisy and are intentionally orthogonal to this phase’s replayability substrate.
