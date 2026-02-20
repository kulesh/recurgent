# ADR 0024 Phase 6 Validation

- Date: 2026-02-20
- Commands: `mise exec -- bundle exec rspec`, `mise exec -- env XDG_STATE_HOME=... ruby examples/calculator.rb`, `mise exec -- env XDG_STATE_HOME=... ruby examples/assistant.rb`

## Test Suite
- Examples: 259
- Failures: 0
- Result: pass

## Calculator Run
- Output checks:
  - `add_ok`: true
  - `multiply_ok`: true
  - `sqrt_latest_ok`: true
  - `runtime_context_ok`: false
  - `sqrt_144_ok`: true
  - `factorial_ok`: true
  - `convert_ok`: true
  - `solve_ok`: true
  - `overall_ok`: false
- Captured values:
  - `add`: "8"
  - `multiply`: "32"
  - `sqrt_latest`: "5.656854249492381"
  - `runtime_context`: "8"
  - `sqrt_144`: "12.0"
  - `factorial`: "3628800"
  - `convert`: "212.0"
  - `solve`: "{equation: \"2x + 5 = 17\", solution: 6.0, variable: \"x\", steps: [\"Original: 2x + 5 = 17\", \"Parsed: 2.0x + 5.0 = 17.0\", \"Subtract 5.0 from both sides: 2.0x = 12.0\", \"Divide both sides by 2.0: x = 6.0\", \"Verification: 2.0 × 6.0 + 5.0 = 17.0\"], verified: true}"
- Log summary: entries=8, status={"ok" => 8}, by_role={"calculator" => 8}
- Ordered execution:
  - 1. depth=0 calculator.add -> ok
  - 2. depth=0 calculator.multiply -> ok
  - 3. depth=0 calculator.sqrt -> ok
  - 4. depth=0 calculator.sqrt -> ok
  - 5. depth=0 calculator.factorial -> ok
  - 6. depth=0 calculator.convert -> ok
  - 7. depth=0 calculator.solve -> ok
  - 8. depth=0 calculator.history -> ok
- Diagnosis: Calculator regression observed: runtime context memory/value continuity drifted.

## Assistant Run
- Output checks:
  - `news_has_google`: true
  - `news_has_yahoo`: true
  - `news_has_nyt`: true
  - `movies_capability_unavailable`: true
  - `recipe_mentions_jaffna`: true
  - `recipe_has_ingredients`: true
  - `recipe_has_instructions`: true
  - `overall_ok`: true
- Log summary: entries=6, status={"error" => 3, "ok" => 3}, by_role={"news_fetcher" => 3, "personal assistant that remembers conversation history" => 3}, outcome_error_types={"guardrail_retry_exhausted" => 1, "execution_error" => 1, "capability_unavailable" => 1}
- Ordered execution:
  - 1. depth=1 news_fetcher.fetch_feed -> error (guardrail_retry_exhausted)
  - 2. depth=1 news_fetcher.fetch_feed -> error (execution_error)
  - 3. depth=1 news_fetcher.fetch_feed -> ok
  - 4. depth=0 personal assistant that remembers conversation history.ask -> ok
  - 5. depth=0 personal assistant that remembers conversation history.ask -> error (capability_unavailable)
  - 6. depth=0 personal assistant that remembers conversation history.ask -> ok
- Diagnosis: Assistant returned expected news coverage, explicit movie capability boundary, and a usable Jaffna Kool recipe.
