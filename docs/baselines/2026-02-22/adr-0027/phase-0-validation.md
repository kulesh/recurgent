# ADR 0027 Phase 0 Validation

- Date: 2026-02-22
- Commands:
  - `mise exec -- bundle exec rubocop`
  - `mise exec -- bundle exec rspec`
  - `mise exec -- env XDG_STATE_HOME=... ruby examples/calculator.rb`
  - `mise exec -- env XDG_STATE_HOME=... ruby examples/assistant.rb` (scripted stdin with 3 required prompts)
- Artifacts:
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-0-rubocop.txt`](logs/phase-0-rubocop.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-0-rspec.txt`](logs/phase-0-rspec.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-0-calculator.txt`](logs/phase-0-calculator.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-0-calculator.jsonl`](logs/phase-0-calculator.jsonl)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-0-assistant.txt`](logs/phase-0-assistant.txt)
  - [`docs/baselines/2026-02-22/adr-0027/logs/phase-0-assistant.jsonl`](logs/phase-0-assistant.jsonl)

## Lint and Test Suite

- RuboCop: pass (`92 files inspected, no offenses`).
- RSpec: pass (`275 examples, 0 failures`).

## Calculator Run (`examples/calculator.rb`)

### Observed Output

- `add(3)` -> `3.0`
- `multiply(4)` -> `20`
- `sqrt(latest_result)` -> `4.47213595499958`
- `runtime_context[:memory] || runtime_context[:value]` -> `20`
- `sqrt(144)` -> `12.0`
- `factorial(10)` -> `3628800`
- `convert(100, celsius->fahrenheit)` -> `212.0`
- `solve('2x + 5 = 17')` -> `[guardrail_retry_exhausted]`
- `history` -> falls back to conversation-history array because method itself failed with `[guardrail_retry_exhausted]`

### Accuracy Assessment

- `add_ok` (expected `8` after `memory=5`): `false`
- `multiply_ok` (expected `32`): `false`
- `sqrt_latest_ok` (expected `sqrt(32)`): `false`
- `runtime_context_ok` (expected `32`): `false`
- `sqrt_144_ok`: `true`
- `factorial_ok`: `true`
- `convert_ok`: `true`
- `solve_ok` (expected numeric solution): `false`
- `history_ok` (method success): `false`
- `overall_ok`: `false`

### Trace What Happened

- Log entries: `8` (all depth `0`, role `calculator`).
- Status breakdown:
  - ok: `add`, `multiply`, `sqrt` (x2), `factorial`, `convert`
  - error: `solve`, `history`
- Error types: `guardrail_retry_exhausted` x2.

Key failure mechanics from log metadata:

1. `solve` exhausted recoverable guardrail retries on `role_profile_continuity_violation`:
   - message indicates return-shape divergence against arithmetic siblings (expected numeric family).
   - generated code returned `Outcome.ok({ equation:, solution:, verification: })` (hash shape), conflicting with numeric sibling methods.
2. `history` exhausted retries on `role_profile_continuity_violation`:
   - message indicates state-key divergence (`memory` vs sibling key usage).
   - generated code returned a hash and mixed key assumptions.
3. `add` and `multiply` diverged on state key (`:value` vs `:memory`), causing semantic drift:
   - `add` ignored `memory=5` and started from `context[:value] || 0`.
   - `multiply` used `context[:memory]`, multiplying `5 * 4` to `20`.

Diagnosis:

- The run confirms continuity enforcement catches severe divergence (`solve`/`history`) but calculator semantics are still unstable in mixed-state-key paths.
- Promotion/readiness infrastructure is not expected to fix calculator semantics by itself in Phase 0; this remains runtime/profile behavior work.

## Assistant Run (`examples/assistant.rb` with required 3 prompts)

### Prompt 1: Top news from Google News, Yahoo, NY Times

Observed:

- Returned Yahoo and NY Times items.
- Google source reported in `errors` as `HTTP 302: Found`.

Trace details:

- Child calls (depth 1):
  - `rss_feed_reader.fetch_rss`: first call `unknown_error` (`undefined method 'content' for String`), then 2 successful retries/alternates.
  - `rss_reader.fetch_feed`: one `http_error` (302), then 2 successes.
- Parent `ask` completed `ok` with partial-source result and provenance.

Accuracy:

- `news_has_google_items`: `false` (Google failed in this run)
- `news_has_yahoo_items`: `true`
- `news_has_nyt_items`: `true`
- `news_overall_ok`: `partial`

### Prompt 2: Action adventure movies playing in theaters

Observed:

- Returned `capability_unavailable` with explicit boundary explanation.

Accuracy:

- `movies_capability_boundary_honest`: `true`
- `movies_listing_success`: `false`

### Prompt 3: Good recipe for Jaffna Kool

Observed:

- Returned `capability_unavailable` and generic advice to search externally.
- Did not provide concrete recipe steps/ingredients.

Accuracy:

- `recipe_mentions_jaffna`: `true`
- `recipe_has_ingredients`: `false`
- `recipe_has_instructions`: `false`
- `recipe_overall_ok`: `false`

### Trace What Happened

- Log entries: `9`
- Status by method:
  - `ask`: `ok` x1, `error` x2
  - `fetch_rss`: `ok` x2, `error` x1
  - `fetch_feed`: `ok` x2, `error` x1
- Error types:
  - `capability_unavailable` x2
  - `http_error` x1
  - `unknown_error` x1

Diagnosis:

- News path is partially functional but brittle against redirect handling (302) and parser shape variation (`String` vs object title nodes).
- Movie and recipe outcomes are boundary-honest but do not meet a “deliver concrete answer” expectation.
- This is consistent with known open-world capability gaps and live-source variability.

## Phase 0 Improvement Contract Check

Expected (Phase 0): introduce machine-checkable simulation gate contract and run-ledger schema.

Observed:

- Added [`specs/contract/v1/simulation-preparedness.contract.yaml`](../../../../specs/contract/v1/simulation-preparedness.contract.yaml).
- Added [`specs/contract/v1/simulation-run-ledger.schema.json`](../../../../specs/contract/v1/simulation-run-ledger.schema.json).
- Added integrity spec: [`runtimes/ruby/spec/contract/simulation_preparedness_contract_spec.rb`](../../../../runtimes/ruby/spec/contract/simulation_preparedness_contract_spec.rb).
- Contract/lint/test checks pass.
- Example behavior remains mixed, which is expected at this phase.
