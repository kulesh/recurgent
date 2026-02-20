# ADR 0024 Phase 4 Validation

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
  - `sqrt_latest_ok`: false
  - `runtime_context_ok`: true
  - `sqrt_144_ok`: true
  - `factorial_ok`: true
  - `convert_ok`: true
  - `solve_ok`: true
  - `overall_ok`: false
- Captured values:
  - `add`: "8"
  - `multiply`: "32"
  - `sqrt_latest`: "0.0"
  - `runtime_context`: "32"
  - `sqrt_144`: "12.0"
  - `factorial`: "3628800"
  - `convert`: "212.0"
  - `solve`: "{solution: \"x = 6.0\", x: 6.0, steps: [\"Original equation: 2x + 5 = 17\", \"Subtract 5.0 from both sides: 2.0x = 12.0\", \"Divide both sides by 2.0: x = 6.0\"], verified: true, metadata: {equation_type: \"linear\", method: \"algebraic_isolation\"}}"
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
- Diagnosis: Calculator regression observed: derived sqrt(latest_result) was incorrect.

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
- Log summary: entries=9, status={"ok" => 8, "error" => 1}, by_role={"web_fetcher" => 3, "rss_parser" => 3, "personal assistant that remembers conversation history" => 3}, outcome_error_types={"capability_unavailable" => 1}
- Ordered execution:
  - 1. depth=1 web_fetcher.fetch_url -> ok
  - 2. depth=1 rss_parser.parse -> ok
  - 3. depth=1 web_fetcher.fetch_url -> ok
  - 4. depth=1 rss_parser.parse -> ok
  - 5. depth=1 web_fetcher.fetch_url -> ok
  - 6. depth=1 rss_parser.parse -> ok
  - 7. depth=0 personal assistant that remembers conversation history.ask -> ok
  - 8. depth=0 personal assistant that remembers conversation history.ask -> error (capability_unavailable)
  - 9. depth=0 personal assistant that remembers conversation history.ask -> ok
- Diagnosis: Assistant returned expected news coverage, explicit movie capability boundary, and a usable Jaffna Kool recipe.
