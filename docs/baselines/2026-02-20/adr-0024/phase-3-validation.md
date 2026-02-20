# ADR 0024 Phase 3 Validation

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
  - `runtime_context_ok`: true
  - `sqrt_144_ok`: true
  - `factorial_ok`: true
  - `convert_ok`: true
  - `solve_ok`: true
  - `overall_ok`: true
- Captured values:
  - `add`: "8"
  - `multiply`: "32"
  - `sqrt_latest`: "5.656854249492381"
  - `runtime_context`: "32"
  - `sqrt_144`: "12.0"
  - `factorial`: "3628800"
  - `convert`: "212.0"
  - `solve`: "6.0"
- Log summary: entries=11, status={"ok" => 10, "error" => 1}, by_role={"calculator" => 10, "converter" => 1}
- Ordered execution:
  - 1. depth=0 calculator.add -> ok
  - 2. depth=0 calculator.multiply -> ok
  - 3. depth=0 calculator.sqrt -> ok
  - 4. depth=1 calculator.sqrt -> ok
  - 5. depth=0 calculator.sqrt -> ok
  - 6. depth=1 calculator.context -> error (missing_argument)
  - 7. depth=0 calculator.factorial -> ok
  - 8. depth=1 converter.convert -> ok
  - 9. depth=0 calculator.convert -> ok
  - 10. depth=0 calculator.solve -> ok
  - 11. depth=0 calculator.history -> ok
- Diagnosis: Calculator baseline behaviors were correct in this phase.

## Assistant Run
- Output checks:
  - `news_has_google`: true
  - `news_has_yahoo`: false
  - `news_has_nyt`: true
  - `movies_capability_unavailable`: true
  - `recipe_mentions_jaffna`: true
  - `recipe_has_ingredients`: true
  - `recipe_has_instructions`: true
  - `overall_ok`: false
- Log summary: entries=9, status={"ok" => 8, "error" => 1}, by_role={"http_fetcher" => 3, "rss_parser" => 3, "personal assistant that remembers conversation history" => 3}, outcome_error_types={"capability_unavailable" => 1}
- Ordered execution:
  - 1. depth=1 http_fetcher.fetch -> ok
  - 2. depth=1 rss_parser.parse -> ok
  - 3. depth=1 http_fetcher.fetch -> ok
  - 4. depth=1 rss_parser.parse -> ok
  - 5. depth=1 http_fetcher.fetch -> ok
  - 6. depth=1 rss_parser.parse -> ok
  - 7. depth=0 personal assistant that remembers conversation history.ask -> ok
  - 8. depth=0 personal assistant that remembers conversation history.ask -> error (capability_unavailable)
  - 9. depth=0 personal assistant that remembers conversation history.ask -> ok
- Diagnosis: Assistant output partially degraded: missing checks news_has_yahoo, overall_ok.
