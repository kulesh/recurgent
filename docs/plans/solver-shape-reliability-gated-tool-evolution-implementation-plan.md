# Solver Shape and Reliability-Gated Tool Evolution Implementation Plan

- Status: draft
- Date: 2026-02-18
- Scope: ADR 0023 rollout (solver-shape evidence model + version-aware promotion lifecycle)

## Objective

Implement ADR 0023 so Recurgent can evolve tools continuously while promoting defaults only when reliability is demonstrated.

Primary outcomes:

1. Solver behavior remains prompt-policy driven, but emits first-class typed Solver Shape evidence.
2. Tool promotion is version-aware (`candidate`, `probation`, `durable`, `degraded`) and policy-gated.
3. Selector preference is driven by scorecard evidence, with deterministic rollback to incumbent durable versions.
4. Cold-start forge-and-use remains fast via lightweight `candidate -> probation`; evidence concentrates at `probation -> durable`.

## Non-Goals

1. Do not replace Tool Builder reasoning with a rigid typed planner.
2. Do not add runtime-autonomous decomposition that bypasses Tool Builder intent.
3. Do not introduce domain-specific policy lanes for news/movies/recipes.
4. Do not change ADR 0017 observational semantics for domain outcomes.

## Design Constraints

1. Prompt policy remains the cognitive contract; typed fields are evidence and policy surfaces.
2. Promotion gates control lifecycle state, not tool-authored domain semantics.
3. Version-aware transitions must be reversible and traceable.
4. Hot-path overhead must remain bounded.
5. Tolerant interface defaults apply for non-gate-critical fields.

## Scope

In scope:

1. `solver_shape` schema capture in dynamic-call telemetry and persistence metadata.
2. Version-scoped reliability scorecards.
3. Promotion policy contract (`v1`) and transition engine.
4. Shadow evaluation mode and controlled enforcement.
5. Selector and prompt integration with lifecycle-aware tool ranking.
6. Migration/backfill strategy for existing durable artifacts.

Out of scope:

1. Lua parity.
2. New external service dependencies for telemetry storage.
3. Global rewrite of existing artifact format in one migration step.

## Current State Snapshot

Already implemented:

1. Prompt-level stance guidance (`Do`, `Shape`, `Forge`, `Orchestrate`).
2. Validation-first retries, contract boundaries, and guardrail normalization.
3. Artifact persistence, selection, and repair telemetry.
4. Boundary referral and user-correction pressure signals.

Current gaps:

1. No canonical solver envelope pairing decision intent with call outcome.
2. Promotion is not explicitly version-aware with incumbent-vs-candidate policy.
3. Reliability thresholds are distributed, not captured as one policy contract.

## Delivery Strategy

Deliver in seven phases. Each phase is independently testable and shippable.

### Phase 0: Contracts, Taxonomy, and Baselines

Goals:

1. Freeze v1 vocabulary for solver shape and lifecycle states.
2. Define policy and scorecard contracts before runtime wiring.
3. Capture pre-change baseline traces.

Implementation:

1. Define canonical enums:
   - `stance`: `do | shape | forge | orchestrate`
   - `promotion_intent`: `none | local_pattern | durable_tool_candidate`
   - `lifecycle_state`: `candidate | probation | durable | degraded`
2. Define scorecard fields and calculation windows.
3. Define `promotion_policy_version` contract (start with `solver_promotion_v1`).
4. Set threshold scope policy:
   - global defaults in v1,
   - capability-class specialization only after observed misfit.
5. Set v1 baseline thresholds:
   - `probation -> durable` requires at least 10 calls across at least 2 sessions,
   - coherence primary metric is `state_key_consistency_ratio`,
   - specialization trigger is class false-hold or false-promotion > 2x global average over meaningful sample.
6. Capture baseline traces from:
   - `examples/calculator.rb`
   - `examples/assistant.rb` (news/movies/recipe prompts)
   - `examples/debate.rb`

Suggested files:

1. `docs/adrs/0023-solver-shape-and-reliability-gated-tool-evolution.md` (reference)
2. `docs/observability.md`
3. `docs/baselines/<date>/...`

Exit criteria:

1. Contracts documented and unambiguous.
2. Baseline traces committed for before/after comparison.

### Phase 1: Solver Shape Telemetry (Observational Only)

Goals:

1. Emit typed `solver_shape` evidence for each dynamic call.
2. Keep behavior unchanged (no promotion policy effects yet).

Implementation:

1. Add solver-shape capture struct/hash to call state.
2. Populate from prompt/runtime context with tolerant defaults:
   - `stance`
   - `capability_summary`
   - `reuse_basis`
   - `contract_intent`
   - `promotion_intent`
3. Persist fields in JSONL logs.
4. Add guardrails:
   - if missing required gate-critical fields, mark `solver_shape_complete=false` and continue (observational mode).

Suggested files:

1. `runtimes/ruby/lib/recurgent/call_state.rb`
2. `runtimes/ruby/lib/recurgent/call_execution.rb`
3. `runtimes/ruby/lib/recurgent/observability.rb`
4. `runtimes/ruby/lib/recurgent/observability_attempt_fields.rb`

Exit criteria:

1. Logs include `solver_shape` fields for new calls.
2. No behavior change in selected artifacts or outcomes.

### Phase 2: Version-Scoped Scorecards

Goals:

1. Introduce per-artifact-version scorecards.
2. Preserve compatibility with existing aggregated metrics.

Implementation:

1. Add version key dimension to scorecard storage:
   - `tool_name`
   - `method_name`
   - `artifact_checksum` (or canonical artifact id)
2. Persist core counters:
   - calls, successes, failures
   - contract pass/fail
   - guardrail retry exhausted
   - outcome retry exhausted
   - wrong boundary count
   - provenance violations (when applicable)
   - coherence signals:
     - `state_key_consistency_ratio`
     - (deferred) `state_key_entropy`
     - (deferred) `sibling_method_state_agreement`
3. Add rolling windows:
   - short (recent stabilization)
   - medium (promotion decision)
4. Keep aggregate counters for backward compatibility.

Suggested files:

1. `runtimes/ruby/lib/recurgent/artifact_metrics.rb`
2. `runtimes/ruby/lib/recurgent/artifact_store.rb`
3. `runtimes/ruby/lib/recurgent/tool_store.rb`

Exit criteria:

1. Scorecards are queryable by artifact version.
2. Existing metrics consumers remain functional.

### Phase 3: Promotion Policy Contract and Shadow Engine

Goals:

1. Implement deterministic transition rules in shadow mode.
2. Compare candidate vs incumbent durable outcomes without changing selector.

Implementation:

1. Define policy contract:
   - `promotion_policy_version: "solver_promotion_v1"`
   - thresholds:
     - min contract pass rate
     - max retry exhaustion counts
     - max boundary mismatches
     - provenance compliance requirement for external-data tools
     - minimum observation window: 10 calls across >=2 sessions for `probation -> durable`
     - coherence floor for sibling-method state consistency (advisory in shadow mode first)
2. Introduce lifecycle state machine in shadow mode:
   - `candidate -> probation -> durable`
   - `* -> degraded` on regression
3. Compare candidate vs incumbent durable within fixed observation window.
4. Emit decision records:
   - `decision: promote | continue_probation | degrade | hold`
   - policy snapshot and rationale fields.
5. Shadow-calibration ledger:
   - `false_promotion` (shadow said promote, later evidence says regression)
   - `false_hold` (shadow said hold/degrade, later evidence says should have promoted)
6. Require minimum shadow duration before enforcement:
   - multi-domain coverage (`calculator`, `assistant`, `debate`)
   - at least one productive cold-start flow where candidate becomes probation in-session.
7. Specialization trigger check:
   - evaluate per capability class misfit ratios,
   - keep global defaults unless class false-hold or false-promotion is >2x global average over meaningful sample.

Suggested files:

1. `runtimes/ruby/lib/recurgent/artifact_selector.rb`
2. `runtimes/ruby/lib/recurgent/artifact_metrics.rb`
3. `runtimes/ruby/lib/recurgent/tool_store.rb`
4. `runtimes/ruby/lib/recurgent/observability.rb`

Exit criteria:

1. Shadow decisions are emitted and stable across deterministic test fixtures.
2. No selector behavior changes yet.

### Phase 4: Controlled Enforcement and Version-Aware Switchover

Goals:

1. Activate policy-gated default selection for new candidates.
2. Keep instant fallback to incumbent durable.

Implementation:

1. Selector preference order:
   - non-degraded durable
   - probation candidate
   - best remaining candidate
2. Enforce switchover only when candidate clears gate policy.
3. On regression, auto-fallback to prior durable and mark candidate degraded.
4. Add kill-switch config:
   - disable enforced transitions
   - return to pre-policy selection mode.
5. Keep `candidate -> probation` transition lightweight:
   - first productive session may advance to probation,
   - durable promotion requires >=10 calls across >=2 sessions plus policy gate pass.

Suggested files:

1. `runtimes/ruby/lib/recurgent/artifact_selector.rb`
2. `runtimes/ruby/lib/recurgent.rb` (runtime config surface)
3. `runtimes/ruby/lib/recurgent/observability.rb`

Exit criteria:

1. Candidate promotion affects selector only after gate pass.
2. Fallback behavior is deterministic and test-covered.

### Phase 5: Prompt and Tool Registry Integration

Goals:

1. Surface lifecycle and reliability hints to Tool Builder prompts.
2. Keep prompt footprint bounded and useful.

Implementation:

1. Extend known-tools metadata rendering with:
   - lifecycle state
   - policy version
   - compact scorecard summary
2. Add ranking preferences:
   - prefer durable tools
   - annotate degraded tools with caution reason
3. Bound injection:
   - top-N tools only
   - compact fields only
   - omit unchanged historical noise.

Suggested files:

1. `runtimes/ruby/lib/recurgent/prompting.rb`
2. `runtimes/ruby/lib/recurgent/known_tool_ranker.rb`

Exit criteria:

1. Prompt shows lifecycle evidence without excessive token bloat.
2. Tool Builder can distinguish incumbent durable vs evolving candidates.

### Phase 6: Migration, Operations, and Governance

Goals:

1. Migrate existing durable tools into the lifecycle model safely.
2. Provide operator workflows and docs for threshold tuning.

Implementation:

1. Migration strategy:
   - legacy durable artifacts enter as `probation` with compatibility flag,
   - promote to `durable` only after minimum evidence window under v1 policy.
2. Add operator workflows:
   - inspect scorecards
   - inspect transition decisions
   - force demote/promote for emergency response (audited action)
3. Document governance:
   - policy version bump process
   - acceptance criteria for threshold changes
   - rollback protocol.

Suggested files:

1. `docs/observability.md`
2. `docs/maintenance.md`
3. `docs/governance.md`
4. `bin/recurgent-tools` (optional operator command surface)

Exit criteria:

1. Legacy artifacts run safely under compatibility mode.
2. Policy tuning/rollback process is documented and repeatable.

## Data Contract Updates (v1)

### Solver Shape Record (Log/Event)

```json
{
  "solver_shape": {
    "stance": "forge",
    "capability_summary": "external_data_retrieval_and_synthesis",
    "reuse_basis": "general capability absent in known tools",
    "contract_intent": {
      "purpose": "fetch and summarize latest headlines",
      "failure_policy": { "on_error": "return_error" }
    },
    "promotion_intent": "durable_tool_candidate",
    "complete": true
  }
}
```

### Version-Scoped Lifecycle Entry

```json
{
  "tool_name": "web_fetcher",
  "method_name": "fetch_url",
  "artifact_id": "sha256:abcd1234",
  "lifecycle_state": "candidate",
  "policy_version": "solver_promotion_v1",
  "incumbent_artifact_id": "sha256:prev9999",
  "last_decision": "continue_probation",
  "last_decision_at": "2026-02-18T20:00:00Z"
}
```

### Promotion Decision Event

```json
{
  "decision_type": "promotion_evaluation",
  "tool_name": "web_fetcher",
  "candidate_artifact_id": "sha256:abcd1234",
  "incumbent_artifact_id": "sha256:prev9999",
  "decision": "promote",
  "policy_version": "solver_promotion_v1",
  "window": "rolling_200_calls",
  "rationale": {
    "contract_pass_rate": 0.98,
    "guardrail_retry_exhausted": 0,
    "outcome_retry_exhausted": 0,
    "wrong_tool_boundary_count": 0,
    "provenance_violations": 0
  }
}
```

## Test Strategy

### Unit Tests

1. Solver-shape field normalization and defaults.
2. Lifecycle transition function for all state paths.
3. Policy threshold evaluation edge cases (exact threshold, empty window, missing data).
4. Version-scoped scorecard updates and rolling-window calculations.

### Integration Tests

1. Candidate and incumbent coexist; selector serves incumbent before promotion.
2. Candidate passes gate and becomes durable.
3. Candidate regresses and is degraded with automatic fallback.
4. Prompt rendering includes compact lifecycle evidence.
5. Candidate from cold-start productive session enters probation without blocking immediate reuse.
6. Candidate does not promote to durable before satisfying 10-call / 2-session minimum.

### Acceptance Tests

1. Deterministic tool evolution flow:
   - build candidate,
   - run probation window,
   - promote or degrade deterministically.
2. External-data scenario:
   - candidate with provenance regressions cannot promote.
3. Stable incumbent safety:
   - user-facing quality remains stable while candidate experiments occur.

### Regression Tests

1. No change to ADR 0017 semantics (no success->error semantic coercion).
2. No change to top-level guardrail normalization behavior (ADR 0022).
3. Existing examples continue to run (`calculator`, `assistant`, `debate`).

## Metrics and Quality Gates

Track and publish per policy version:

1. promotion attempt count
2. promotion success rate
3. degraded-after-promotion rate
4. fallback frequency
5. median time from candidate -> durable
6. contract pass-rate delta (candidate vs incumbent)
7. false-promotion rate (from shadow/enforced audits)
8. false-hold rate (from shadow/enforced audits)
9. coherence trend delta (`state_key_consistency_ratio`) candidate vs incumbent
10. capability-class misfit multiplier vs global average (false-hold and false-promotion)

Release gate for enforcement phases:

1. no increase in guardrail-retry-exhausted rate above agreed threshold,
2. no increase in user-correction rate on incumbent-replaced interfaces,
3. deterministic fallback validated in acceptance traces,
4. false-promotion and false-hold rates under agreed control limits.
5. no capability class exceeds 2x global misfit baseline unless explicitly approved for profile specialization.

## Rollout Controls

1. Feature flags:
   - `solver_shape_capture_enabled` (default: on after Phase 1)
   - `promotion_shadow_mode_enabled` (default: on in Phase 3)
   - `promotion_enforcement_enabled` (default: off until Phase 4 gate)
2. Emergency rollback:
   - disable enforcement flag,
   - force selector to incumbent durable only.
3. Policy version rollback:
   - maintain previous policy definitions for reversible downgrades.

## Risks and Mitigations

1. Risk: premature promotion under sparse data.
   - Mitigation: minimum observation window + probation floor before promotion.
2. Risk: over-conservative holds suppress useful tools.
   - Mitigation: track false-hold rate and tune thresholds using shadow ledger evidence.
3. Risk: selector churn from oscillating candidates.
   - Mitigation: cooldown windows and hysteresis thresholds.
4. Risk: prompt bloat from reliability metadata.
   - Mitigation: top-N bounded summaries and compact fields.
5. Risk: migration disruption for existing durable artifacts.
   - Mitigation: compatibility mode + gradual reclassification.
6. Risk: overfitting policy to one domain.
   - Mitigation: cross-domain acceptance suite (`calculator`, `assistant`, `debate`).

## Completion Checklist

1. ADR 0023 is linked from this plan and remains internally consistent.
2. Solver-shape fields are emitted and documented.
3. Version-scoped scorecards persist and are queryable.
4. Shadow policy decisions are visible in logs.
5. Enforcement and fallback are feature-flagged and tested.
6. Prompt and selector integration are bounded and stable.
7. `mise exec -- bundle exec rspec` passes.
8. `mise exec -- bundle exec rubocop` passes.
