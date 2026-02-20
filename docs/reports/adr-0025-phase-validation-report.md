# ADR 0025 Phase Validation Report

- Date: 2026-02-19
- Scope: [`docs/plans/awareness-substrate-authority-boundary-implementation-plan.md`](../plans/awareness-substrate-authority-boundary-implementation-plan.md)
- Required checks per phase:
  1. Full Ruby test suite (`bundle exec rspec`)
  2. Calculator example ([`runtimes/ruby/examples/calculator.rb`](../../runtimes/ruby/examples/calculator.rb))
  3. Assistant example ([`runtimes/ruby/examples/assistant.rb`](../../runtimes/ruby/examples/assistant.rb)) with:
     - `What's the top news items in Google News, Yahoo! News, and NY Times`
     - `What's are the action adventure movies playing in theaters`
     - `What's a good recipe for Jaffna Kool`
  4. Log inspection and diagnosis for calculator + assistant runs

## Phase 0

### Changes

- Baseline validation capture for ADR 0025 rollout (no runtime behavior changes yet).
- Validation artifacts captured under [`tmp/phase-validation-0025/phase-0/`](../../tmp/phase-validation-0025/phase-0).

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-0/xdg bundle exec rspec`
- Result: PASS
- Evidence: [`tmp/phase-validation-0025/phase-0/rspec.txt`](../../tmp/phase-validation-0025/phase-0/rspec.txt)
- Summary:
  - `243 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-0/xdg ruby examples/calculator.rb`
- Result: PASS
- Evidence: [`tmp/phase-validation-0025/phase-0/calculator.txt`](../../tmp/phase-validation-0025/phase-0/calculator.txt)
- Output checks:
  - `add(3) => 8`
  - `multiply(4) => 32`
  - `sqrt(32) => 5.65685424949238`
  - `sqrt(144) => 12.0`
  - `factorial(10) => 3628800`
  - `convert(100, celsius->fahrenheit) => 212.0`
  - `solve('2x + 5 = 17') => 6.0`
- Accuracy assessment: Correct for all displayed operations.

#### Assistant example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-0/xdg ruby examples/assistant.rb < /Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-0/assistant_input.txt`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0025/phase-0/assistant.txt`](../../tmp/phase-validation-0025/phase-0/assistant.txt)
- Request 1 (top news):
  - Returned large aggregated payload (`summary: "Retrieved 109 news items from 3 sources"`), with provenance refs for Google News, Yahoo News, and NYT feeds.
  - Accuracy: Source coverage and provenance structure are strong; item ranking quality is noisy because output returns many items rather than concise "top items."
- Request 2 (action-adventure movies in theaters):
  - Returned typed error `capability_unavailable`.
  - Accuracy: truthful limitation response; request remains unsatisfied.
- Request 3 (Jaffna Kool recipe):
  - Returned structured recipe with ingredients, instructions, tips, and variations.
  - Accuracy: plausible and useful.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation-0025/phase-0/recurgent.jsonl` (`17` entries)
- Trace summary:
  - Roles:
    - `calculator`: `8` entries
    - `personal assistant that remembers conversation history`: `3` top-level `ask` entries
    - `http_fetcher`: `3` delegated entries
    - `rss_parser`: `3` delegated entries
  - Assistant top-level outcomes:
    - `ask(news)`: `ok` (`duration_ms=42788.2`)
    - `ask(movies)`: `error(capability_unavailable)` (`duration_ms=11887.8`)
    - `ask(recipe)`: `ok` (`duration_ms=23753.8`)
- Diagnosis:
  - What went well:
    - Baseline is stable (`243` passing specs).
    - Calculator deterministic path is healthy.
    - News query used delegated fetch+parse tools with provenance.
    - Recipe response quality is strong.
  - Needs improvement:
    - Movie-theater request still has no tolerant fallback.
    - News response should prioritize concise top items rather than very large dumps.

## Phase 1

### Changes

- Added observational self-model capture fields into call state:
  - `self_model`
  - `awareness_level`
  - `authority`
  - `active_contract_version`
  - `active_role_profile_version`
  - `execution_snapshot_ref`
  - `evolution_snapshot_ref`
- Added read-only `Agent#self_model` method.
- Added runtime toggle `self_model_capture_enabled` (`RECURGENT_SELF_MODEL_CAPTURE_ENABLED`, default `true`).
- Extended observability mapping and spec coverage for the new fields.

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-1/xdg bundle exec rspec`
- Result: PASS
- Evidence: [`tmp/phase-validation-0025/phase-1/rspec.txt`](../../tmp/phase-validation-0025/phase-1/rspec.txt)
- Summary:
  - `245 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-1/xdg ruby examples/calculator.rb`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0025/phase-1/calculator.txt`](../../tmp/phase-validation-0025/phase-1/calculator.txt)
- Output checks:
  - `add(3) => 3` (expected memory-based chain result was `8`)
  - `multiply(4) => 12` (expected memory-based chain result was `32`)
  - `sqrt(12) => 3.4641016151377544`
  - `sqrt(144) => 12.0`
  - `factorial(10) => 3628800`
  - `convert(100, celsius->fahrenheit) => 212.0`
  - `solve('2x + 5 = 17')` returned structured solved payload with `solution: 6.0`
- Accuracy assessment:
  - Arithmetic chain state continuity regressed (`memory` not used as accumulator).
  - Other numeric operations and equation solving remained correct.

#### Assistant example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-1/xdg ruby examples/assistant.rb < /Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-1/assistant_input.txt`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0025/phase-1/assistant.txt`](../../tmp/phase-validation-0025/phase-1/assistant.txt)
- Request 1 (top news):
  - Returned multi-source items from Google/Yahoo/NYT with provenance refs (`source_count: 3`).
  - Accuracy: structurally sound; still broad/noisy rather than a concise “top items” shortlist.
- Request 2 (action-adventure movies in theaters):
  - Returned `capability_unavailable`.
  - Accuracy: truthful limitation, request unsatisfied.
- Request 3 (Jaffna Kool recipe):
  - Returned `capability_limit` instead of recipe.
  - Accuracy: regression from Phase 0 behavior.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation-0025/phase-1/recurgent.jsonl` (`17` entries)
- Self-model telemetry checks:
  - `self_model` present on all `17` entries.
  - `awareness_level` logged as `l3` on all entries.
  - `authority` logged consistently as `{observe: true, propose: true, enact: false}`.
  - `execution_snapshot_ref` and `evolution_snapshot_ref` present on all entries.
  - `active_contract_version` and `active_role_profile_version` remained `nil` in this baseline flow.
- Trace summary:
  - Same role distribution as Phase 0 (`calculator:8`, `assistant:3`, `http_fetcher:3`, `rss_parser:3`).
  - Assistant top-level outcomes: `ok` (news), `error(capability_unavailable)` (movies), `error(capability_limit)` (recipe).
- Diagnosis:
  - What went well:
    - Self-model fields are consistently captured without runtime failures.
    - Test suite remained green after adding observational awareness surfaces.
  - Needs improvement:
    - Awareness-level derivation is over-eager (`l3` everywhere due evolution ref derivation), so it currently lacks discrimination between L1/L2/L3.
    - Calculator continuity regression and assistant recipe regression persist and are orthogonal to awareness capture.

## Phase 2

### Changes

- Added proposal artifact persistence module:
  - [`runtimes/ruby/lib/recurgent/proposal_store.rb`](../../runtimes/ruby/lib/recurgent/proposal_store.rb)
- Added proposal storage path:
  - `_toolstore_proposals_path` in `ToolStorePaths`.
- Added minimal Agent API:
  - `propose(proposal_type:, target:, proposed_diff_summary:, evidence_refs:, metadata:)`
  - `proposals(status: nil, limit: nil)`
  - `proposal(proposal_id)`
- Added spec coverage for proposal persistence and non-mutation behavior.

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-2/xdg bundle exec rspec`
- Result: PASS
- Evidence: [`tmp/phase-validation-0025/phase-2/rspec.txt`](../../tmp/phase-validation-0025/phase-2/rspec.txt)
- Summary:
  - `246 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-2/xdg ruby examples/calculator.rb`
- Result: PASS
- Evidence: [`tmp/phase-validation-0025/phase-2/calculator.txt`](../../tmp/phase-validation-0025/phase-2/calculator.txt)
- Output checks:
  - `add(3) => 8`
  - `multiply(4) => 32`
  - `sqrt(32) => 5.656854249492381`
  - `sqrt(144) => 12.0`
  - `factorial(10) => 3628800`
  - `convert(100, celsius->fahrenheit) => 212.0`
  - `solve('2x + 5 = 17')` returned `solution: 6.0` with steps
- Accuracy assessment: Correct across displayed outputs.

#### Assistant example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-2/xdg ruby examples/assistant.rb < /Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-2/assistant_input.txt`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0025/phase-2/assistant.txt`](../../tmp/phase-validation-0025/phase-2/assistant.txt)
- Request 1 (top news):
  - Returned `10` top items with provenance, but only `2` sources represented (Google News + NYT).
  - Accuracy: partially satisfies source requirement; Yahoo source missing in output list.
- Request 2 (action-adventure movies in theaters):
  - Returned `capability_unavailable`.
  - Accuracy: truthful limitation, request unsatisfied.
- Request 3 (Jaffna Kool recipe):
  - Returned detailed structured recipe payload (successful).
  - Accuracy: plausible and useful.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation-0025/phase-2/recurgent.jsonl` (`17` entries)
- Trace summary:
  - Top-level outcomes:
    - calculator `8` calls: all `ok`
    - assistant `3` calls: `ok`, `error(capability_unavailable)`, `ok`
  - Awareness fields remained present with `awareness_level=l3` on all top-level calls.
- Proposal protocol verification:
  - Proposal file was not created during examples (`proposals.json` absent), confirming no implicit auto-proposal side effects in standard flows.
- Diagnosis:
  - What went well:
    - Proposal protocol landed without regressions; tests and baseline flows remain stable.
    - Calculator baseline recovered to expected chained behavior this phase.
  - Needs improvement:
    - Assistant news source balancing still inconsistent (Yahoo omitted in this run).
    - Awareness level still saturates at `l3` and needs calibration to meaningfully distinguish L1/L2/L3.

## Phase 3

### Changes

- Added authority boundary module:
  - [`runtimes/ruby/lib/recurgent/authority.rb`](../../runtimes/ruby/lib/recurgent/authority.rb)
- Added runtime authority config:
  - `authority_enforcement_enabled`
  - `authority_maintainers`
- Added proposal mutation APIs with enforcement:
  - `approve_proposal`
  - `reject_proposal`
  - `apply_proposal`
- Added typed denial behavior:
  - unauthorized mutation returns `Outcome.error(error_type: "authority_denied")`
- Added spec coverage for:
  - unauthorized denial
  - approval-before-apply requirement
  - maintainer-controlled approval/apply transitions

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-3/xdg bundle exec rspec`
- Result: PASS
- Evidence: [`tmp/phase-validation-0025/phase-3/rspec.txt`](../../tmp/phase-validation-0025/phase-3/rspec.txt)
- Summary:
  - `248 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-3/xdg ruby examples/calculator.rb`
- Result: PASS
- Evidence: [`tmp/phase-validation-0025/phase-3/calculator.txt`](../../tmp/phase-validation-0025/phase-3/calculator.txt)
- Output checks:
  - `add(3) => 8`
  - `multiply(4) => 32`
  - `sqrt(32) => 5.656854249492381`
  - `sqrt(144) => 12.0`
  - `factorial(10) => 3628800`
  - `convert(100, celsius->fahrenheit) => 212.0`
  - `solve('2x + 5 = 17') => 6.0`
- Accuracy assessment: Correct for all displayed operations.

#### Assistant example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-3/xdg ruby examples/assistant.rb < /Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-3/assistant_input.txt`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0025/phase-3/assistant.txt`](../../tmp/phase-validation-0025/phase-3/assistant.txt)
- Request 1 (top news):
  - Returned source breakdown with Google + NYT success but Yahoo feed failure:
    - error: `NoMethodError - undefined method 'request_uri' for an instance of URI::Generic`
  - Summary said `Fetched 2 of 3 feeds successfully`.
  - Accuracy: partial success with explicit failure disclosure.
- Request 2 (action-adventure movies in theaters):
  - Returned `capability_unavailable`.
  - Accuracy: truthful limitation, request unsatisfied.
- Request 3 (Jaffna Kool recipe):
  - Returned detailed structured recipe payload.
  - Accuracy: plausible and useful.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation-0025/phase-3/recurgent.jsonl` (`16` entries)
- Trace summary:
  - Top-level calls:
    - calculator `8` calls: all `ok`
    - assistant `3` calls: `ok`, `error(capability_unavailable)`, `ok`
  - `authority_denied` entries in this baseline run: `0` (expected; no proposal mutation methods invoked in examples)
- Diagnosis:
  - What went well:
    - Authority enforcement rollout did not regress normal runtime flows.
    - Calculator remained stable.
    - News path now exposes per-source partial failures explicitly instead of fabricating coverage.
  - Needs improvement:
    - Yahoo fetch bug (`URI::Generic#request_uri`) caused a recurring partial-news failure.
    - Movie listing capability remains unresolved.

## Phase 4

### Changes

- Completed governance/operator workflow for proposal artifacts:
  - Added proposal commands to [`bin/recurgent-tools`](../../bin/recurgent-tools):
    - `proposals`
    - `approve-proposal <id>`
    - `reject-proposal <id>`
    - `apply-proposal <id>`
- Documented review/apply governance protocol in:
  - [`docs/governance.md`](../governance.md)
  - [`docs/maintenance.md`](../maintenance.md)

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-4/xdg bundle exec rspec`
- Result: PASS
- Evidence: [`tmp/phase-validation-0025/phase-4/rspec.txt`](../../tmp/phase-validation-0025/phase-4/rspec.txt)
- Summary:
  - `248 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-4/xdg ruby examples/calculator.rb`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0025/phase-4/calculator.txt`](../../tmp/phase-validation-0025/phase-4/calculator.txt)
- Output checks:
  - `add(3) => 8`
  - `multiply(4) => 32`
  - `sqrt(32) => 5.656854249492381`
  - `sqrt(144) => 12.0`
  - `factorial(10)` failed with execution error (`undefined local variable or method 'context'`)
  - `convert(100, celsius->fahrenheit) => 212.0`
  - `solve('2x + 5 = 17') => 6.0`
- Accuracy assessment:
  - Most operations were correct.
  - `factorial` correctness regressed in this run due generated-code error.

#### Assistant example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-4/xdg ruby examples/assistant.rb < /Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-4/assistant_input.txt`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0025/phase-4/assistant.txt`](../../tmp/phase-validation-0025/phase-4/assistant.txt)
- Request 1 (top news):
  - Returned Google News, Yahoo! News, and NY Times lists with provenance refs.
  - Accuracy: source coverage satisfied; still verbose/broad instead of concise ranking.
- Request 2 (action-adventure movies in theaters):
  - Returned `capability_unavailable`.
  - Accuracy: truthful limitation; request unsatisfied.
- Request 3 (Jaffna Kool recipe):
  - Returned complete structured recipe.
  - Accuracy: plausible and useful.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation-0025/phase-4/recurgent.jsonl` (`14` entries)
- Trace summary:
  - Roles:
    - `calculator`: `8`
    - `rss_feed_fetcher`: `3`
    - `personal assistant that remembers conversation history`: `3`
  - Top-level outcomes:
    - calculator: `7 ok`, `1 error(execution)`
    - assistant: `2 ok`, `1 error(capability_unavailable)`
- Diagnosis:
  - What went well:
    - Phase 4 governance/CLI additions did not break the test suite.
    - Proposal workflow surface is now executable and documented.
    - Assistant news path returned full three-source coverage in this run.
  - Needs improvement:
    - Calculator `factorial` remains nondeterministic in generated path.
    - Movie-theater request remains unsupported.

## Phase 5

### Changes

- Added context-scope pressure telemetry in runtime metadata/logging:
  - `namespace_key_collision_count`
  - `namespace_multi_lifetime_key_count`
  - `namespace_continuity_violation_count`
- Added role-level operator query:
  - `bin/recurgent-tools namespace-pressure <role>`
- Added evidence-gate thresholds and process docs:
  - [`docs/observability.md`](../observability.md)
  - [`docs/maintenance.md`](../maintenance.md)
- Added spec coverage for namespace-pressure metrics and logging fields.

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-5/xdg bundle exec rspec`
- Result: PASS
- Evidence: [`tmp/phase-validation-0025/phase-5/rspec.txt`](../../tmp/phase-validation-0025/phase-5/rspec.txt)
- Summary:
  - `249 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-5/xdg ruby examples/calculator.rb`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0025/phase-5/calculator.txt`](../../tmp/phase-validation-0025/phase-5/calculator.txt)
- Output checks:
  - `add(3) => 8`
  - `multiply(4) => 32`
  - `sqrt(32) => 5.656854249492381`
  - `sqrt(144) => 12.0`
  - `factorial(10) => 3628800`
  - `convert(100, celsius->fahrenheit) => 212.0`
  - `solve('2x + 5 = 17') => 6.0`
  - `history` returned list payload but included latest call with `provider` error status
- Accuracy assessment:
  - Core arithmetic and equation solving were correct.
  - History rendering path showed provider instability.

#### Assistant example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-5/xdg ruby examples/assistant.rb < /Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-5/assistant_input.txt`
- Result: FAIL (provider connectivity)
- Evidence: [`tmp/phase-validation-0025/phase-5/assistant.txt`](../../tmp/phase-validation-0025/phase-5/assistant.txt)
- Request outcomes:
  - Request 1: `error(provider)` connection error.
  - Request 2: `error(provider)` connection error.
  - Request 3: `error(provider)` connection error.
- Accuracy assessment:
  - Could not evaluate semantic accuracy due upstream provider connection failures.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation-0025/phase-5/recurgent.jsonl` (`11` entries)
- Trace summary:
  - Roles:
    - `calculator`: `8`
    - `personal assistant that remembers conversation history`: `3`
  - Top-level outcomes:
    - calculator: `7 ok`, `1 error(provider)` (`history`)
    - assistant: `3 error(provider)`
- Namespace-pressure telemetry observations (from this baseline flow):
  - Max `namespace_key_collision_count`: `0`
  - Max `namespace_multi_lifetime_key_count`: `0`
  - Max `namespace_continuity_violation_count`: `0`
- CLI smoke check:
  - Command: `bin/recurgent-tools namespace-pressure "rss_feed_fetcher" --root /Users/kulesh/dev/actuator/tmp/phase-validation-0025/phase-4/xdg/recurgent/tools`
  - Output showed zero pressure and stable `state_key_consistency_ratio: 1.0`.
- Evidence-gate decision:
  - Context-scope migration trigger **not met** with current traces.
  - Continue telemetry collection before drafting follow-up context-scope storage ADR.
- Diagnosis:
  - What went well:
    - Phase 5 instrumentation and operator query landed without test regressions.
    - Namespace-pressure fields are present and queryable.
  - Needs improvement:
    - Provider connectivity instability blocked assistant validation.
    - Need additional successful assistant traces before making confidence claims on post-phase behavior quality.

## Post-Phase Connectivity Rerun (2026-02-19)

### Goal

Re-run the full validation loop after observed provider connectivity instability to confirm current runtime behavior on a clean isolated state root.

### Validation

#### Full test suite

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/connection-rerun-20260219/xdg bundle exec rspec`
- Result: PASS
- Evidence: [`tmp/phase-validation-0025/connection-rerun-20260219/rspec.txt`](../../tmp/phase-validation-0025/connection-rerun-20260219/rspec.txt)
- Summary:
  - `249 examples, 0 failures`

#### Calculator example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/connection-rerun-20260219/xdg ruby examples/calculator.rb`
- Result: PARTIAL
- Evidence: [`tmp/phase-validation-0025/connection-rerun-20260219/calculator.txt`](../../tmp/phase-validation-0025/connection-rerun-20260219/calculator.txt)
- Output checks:
  - `add(3) => 8`
  - `multiply(4) => 32`
  - `sqrt(32) => 5.656854249492381`
  - `sqrt(144) => 12.0`
  - `factorial(10) => 3628800`
  - `convert(100, celsius->fahrenheit) => 212.0`
  - `solve('2x + 5 = 17') => 8.5` (incorrect; expected `6.0`)
- Accuracy assessment:
  - Most arithmetic operations are correct.
  - `solve` remains semantically unstable and can return incorrect algebra while still passing structural success criteria.

#### Assistant example

- Command: `cd runtimes/ruby && XDG_STATE_HOME=/Users/kulesh/dev/actuator/tmp/phase-validation-0025/connection-rerun-20260219/xdg ruby examples/assistant.rb < /Users/kulesh/dev/actuator/tmp/phase-validation-0025/connection-rerun-20260219/assistant_input.txt`
- Result: PARTIAL (functional with one known capability gap)
- Evidence: [`tmp/phase-validation-0025/connection-rerun-20260219/assistant.txt`](../../tmp/phase-validation-0025/connection-rerun-20260219/assistant.txt)
- Request 1 (top news):
  - Returned `15` headlines across Google News, Yahoo! News, NY Times with provenance.
  - Accuracy: source coverage achieved; output still broad/noisy for “top items”.
- Request 2 (action-adventure movies in theaters):
  - Returned `capability_unavailable`.
  - Accuracy: truthful limitation; request remains unsatisfied.
- Request 3 (Jaffna Kool recipe):
  - Returned structured recipe with provenance note.
  - Accuracy: plausible and useful.

#### Log inspection and diagnosis

- Log file: `tmp/phase-validation-0025/connection-rerun-20260219/recurgent.jsonl` (`18` entries)
- Trace summary:
  - Roles:
    - `calculator`: `8`
    - `web_fetcher`: `4`
    - `rss_parser`: `3`
    - `personal assistant that remembers conversation history`: `3`
  - Top-level outcomes:
    - calculator: `8 ok`
    - assistant: `2 ok`, `1 error(capability_unavailable)`
- Namespace-pressure telemetry:
  - Max `namespace_key_collision_count`: `0`
  - Max `namespace_multi_lifetime_key_count`: `0`
  - Max `namespace_continuity_violation_count`: `0`

## Cross-Phase Learnings (Phase 0 -> Phase 5)

### What improved as expected

1. **Infrastructure stability and observability improved**
   - Tests remained green through rollouts (`243 -> 249` examples, all passing per phase-end runs).
   - Self-model fields and authority surfaces became explicit and queryable.
   - Proposal workflow moved from concept to executable CLI + governance protocol.
2. **Authority boundary behavior landed correctly**
   - Unauthorized mutation attempts return typed `authority_denied`.
   - Apply flow requires explicit approval and maintains audit metadata.
3. **Phase 5 telemetry goal was met**
   - Namespace-pressure fields were emitted and exposed via operator CLI.
   - Evidence-gate decision became explicit rather than intuition-driven.

### What did not improve (or improved less than expected)

1. **Semantic correctness of generated behavior is still unstable**
   - Calculator runs still showed nondeterministic semantic failures across phases (`factorial` and `solve` regressions in some runs).
   - Latest rerun still produced incorrect algebra result for `solve` despite overall “ok” outcome.
2. **Assistant capability gap for movie listings remains unresolved**
   - `capability_unavailable` persisted in every successful assistant run.
3. **News quality remains noisy**
   - Source coverage improved intermittently, but concise ranking/selection quality is inconsistent.

### What regressed unexpectedly during rollout windows

1. **Provider/connectivity instability in late validation runs**
   - Phase 5 final run previously failed all assistant prompts with provider connection errors.
   - Connectivity rerun confirmed this was environmental/transient, not a persistent deterministic code-path failure.
2. **Occasional source-specific fetch/parser failures**
   - Yahoo fetch/parser instability appeared in some earlier phases; absent in latest rerun.

### Core takeaway

The key claim held: promotion/awareness/authority infrastructure improved **observability and governance**, but it does not by itself guarantee **semantic correctness**. Reliability and governance are now stronger; role-level semantic contracts (especially for deterministic calculator behaviors) still need tighter correctness pressure.
