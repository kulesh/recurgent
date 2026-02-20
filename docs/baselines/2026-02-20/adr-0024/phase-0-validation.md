# ADR 0024 Phase 0 Validation

- Date: 2026-02-20
- Commands: `mise exec -- bundle exec rspec`, `mise exec -- env XDG_STATE_HOME=... ruby examples/calculator.rb`, `mise exec -- env XDG_STATE_HOME=... ruby examples/assistant.rb`

## Test Suite
- Examples: 249
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
  - `convert_ok`: false
  - `solve_ok`: true
  - `overall_ok`: false
- Captured values:
  - `add`: "8"
  - `multiply`: "32"
  - `sqrt_latest`: "5.656854249492381"
  - `runtime_context`: "32"
  - `sqrt_144`: "12.0"
  - `factorial`: "3628800"
  - `convert`: "{original: {value: 100, unit: \"celsius\"}, converted: {value: 212.0, unit: \"fahrenheit\"}, formula: \"celsius to fahrenheit\", result: 212.0}"
  - `solve`: "6.0"
- Log summary: entries=0, status={}, by_role={}
- Ordered execution:
- Diagnosis: Calculator regression observed: .

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
- Log summary: entries=0, status={}, by_role={}, outcome_error_types={}
- Ordered execution:
- Diagnosis: Assistant returned expected news coverage, explicit movie capability boundary, and a usable Jaffna Kool recipe.
