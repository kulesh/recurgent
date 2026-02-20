# ADR 0024 Phase 1 Validation

- Date: 2026-02-20
- Commands: `mise exec -- bundle exec rspec`, `mise exec -- env XDG_STATE_HOME=... ruby examples/calculator.rb`, `mise exec -- env XDG_STATE_HOME=... ruby examples/assistant.rb`

## Test Suite
- Examples: 252
- Failures: 0
- Result: pass

## Calculator Run
- Output checks:
  - `add_ok`: true
  - `multiply_ok`: false
  - `sqrt_latest_ok`: false
  - `runtime_context_ok`: false
  - `sqrt_144_ok`: true
  - `factorial_ok`: false
  - `convert_ok`: true
  - `solve_ok`: true
  - `overall_ok`: false
- Captured values:
  - `add`: "8"
  - `multiply`: "[execution] Execution error in calculator.multiply: undefined method '*' for an instance of Hash"
  - `sqrt_latest`: "2.8284271247461903"
  - `runtime_context`: "2.8284271247461903"
  - `sqrt_144`: "12.0"
  - `factorial`: "{value: 3628800, computation: \"10!\", method: \"factorial\"}"
  - `convert`: "212.0"
  - `solve`: "{equation: \"2x + 5 = 17\", solution: 6.0, steps: [\"Original: 2x + 5 = 17\", \"Parsed: 2.0x + 5.0 = 17.0\", \"Subtract 5.0 from both sides: 2.0x = 12.0\", \"Divide by 2.0: x = 6.0\"], summary: \"Solved 2x + 5 = 17: x = 6.0\"}"
- Log summary: entries=0, status={}, by_role={}
- Ordered execution:
- Diagnosis: Calculator regression observed: multiply drifted from expected state/value continuity; derived sqrt(latest_result) was incorrect; runtime context memory/value continuity drifted.

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
