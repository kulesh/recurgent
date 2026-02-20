# ADR-0024 Scope-Hardcut Validation Report

Date: 2026-02-20

## Scope
Validation after scope-first role-profile hard cut (`scope: all_methods|explicit_methods`, `all_methods` default) and continuity observation fix.

Evidence root:
- [`tmp/phase-validation-0024-scope-hardcut/phase-1-rerun/`](../../tmp/phase-validation-0024-scope-hardcut/phase-1-rerun)
- [`tmp/phase-validation-0024-scope-hardcut/phase-1-rerun/rspec.txt`](../../tmp/phase-validation-0024-scope-hardcut/phase-1-rerun/rspec.txt)
- [`tmp/phase-validation-0024-scope-hardcut/phase-1-rerun/calculator.txt`](../../tmp/phase-validation-0024-scope-hardcut/phase-1-rerun/calculator.txt)
- [`tmp/phase-validation-0024-scope-hardcut/phase-1-rerun/assistant.txt`](../../tmp/phase-validation-0024-scope-hardcut/phase-1-rerun/assistant.txt)
- `tmp/phase-validation-0024-scope-hardcut/phase-1-rerun/xdg/recurgent/recurgent.jsonl`
- [`tmp/phase-validation-0024-scope-hardcut/phase-1-rerun/log_summary.txt`](../../tmp/phase-validation-0024-scope-hardcut/phase-1-rerun/log_summary.txt)

## 1) Full Test Suite
- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=<phase-xdg> bundle exec rspec`
- Result: `259 examples, 0 failures`
- Assessment: Pass.

## 2) Calculator Example
- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=<phase-xdg> ruby examples/calculator.rb`

Run outcomes:
1. `calc.add(3)` -> `8` (correct)
2. `calc.multiply(4)` -> `32` (correct)
3. `calc.sqrt(32)` -> `5.656854249492381` (correct)
4. `calc.sqrt(144)` -> `12.0` (correct)
5. `calc.factorial(10)` -> `3628800` (correct)
6. `calc.convert(100, from: 'celsius', to: 'fahrenheit')` -> `212.0` (correct)
7. `calc.solve('2x + 5 = 17')` -> `guardrail_retry_exhausted` (incorrect; expected a solved value such as `x=6`)
8. `calc.history` -> method returned error (`guardrail_retry_exhausted`), script printed fallback `context[:conversation_history]`

Log diagnosis (`calculator` top-level calls: 8):
- `ok`: 6, `error`: 2.
- Role-profile compliance:
  - Passed for `add`, `multiply`, both `sqrt`, `factorial`, `convert`.
  - Failed for `solve` and `history` (`shared_state_slot_drift`), then retries exhausted.
- Repair/guardrail behavior:
  - `multiply` and `convert` each recovered from one continuity guardrail violation and succeeded.
  - `factorial` recovered from one execution error and succeeded.

What went well:
- Deterministic arithmetic path improved materially (factorial/convert now correct in this rerun).
- Continuity guard correctly enforced shared-state consistency and prevented silent drift.

Needs improvement:
- `solve` remains semantically unstable under continuity constraints.
- `history` currently coupled to prior drift and fails after `solve` exhaustion.

## 3) Personal Assistant Example
- Command: `cd runtimes/ruby && mise exec -- env XDG_STATE_HOME=<phase-xdg> ruby examples/assistant.rb < assistant_input.txt`
- Requests:
  1. Top news in Google News, Yahoo! News, NY Times
  2. Action-adventure movies in theaters
  3. Recipe for Jaffna Kool

Run outcomes:
1. News request -> `ok` (hash with headlines + provenance)
   - Included items from all 3 requested sources.
   - Provenance included URIs and retrieval mode (`live`).
   - Accuracy: mostly correct for source coverage; output is overlong (not tightly “top items”).
2. Movies-in-theaters request -> `error` (`missing_capability`)
   - Accuracy: capability declaration is honest, but user intent is unmet.
3. Jaffna Kool request -> `ok` (structured recipe with ingredients and instructions)
   - Accuracy: good practical recipe output.

Log diagnosis (`assistant` top-level calls: 3):
- `ok`: 2, `error`: 1.
- Delegation observed: `news_aggregator.aggregate_news` and `news_aggregator.fetch_headlines` (both `ok`).
- First two assistant calls had one guardrail recovery each before final outcome.
- Assistant role-profile compliance remained `passed: true` for all three calls.

What went well:
- News aggregation flow executed with source provenance and successful delegated tool calls.
- Recipe flow produced useful structured output.

Needs improvement:
- No movie-theater capability path yet; add dedicated listings tool/dependency contract.
- News response should constrain output length/ranking to true “top items”.

## 4) Expected vs Observed Delta
Expected improvements:
- Scope-hardcut schema consistency and safer `all_methods` coordination.
- Better continuity enforcement with fewer false holds.

Observed:
- Achieved schema consistency (`all_methods` default works; tests green).
- In-session sibling observation now works; spurious synthetic method-name pollution removed.
- Continuity guard enforcement is active and effective.
- Semantic correctness still uneven outside core arithmetic path (`solve`, `history`) and missing-capability user intents (movies).

## 5) Immediate Follow-ups
1. Add a calculator contract/profile constraint for algebra solving semantics (or route `solve` to a dedicated solver tool with explicit state contract).
2. Add theater-listings capability/tool (API-backed) to satisfy movie requests.
3. Add prompt/output constraints for “top N” headline summarization to avoid oversized raw dumps.
