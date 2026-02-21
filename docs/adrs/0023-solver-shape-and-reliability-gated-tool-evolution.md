# ADR 0023: Solver Shape and Reliability-Gated Tool Evolution

- Status: accepted
- Date: 2026-02-18
- Updated: 2026-02-20

## Context

Recurgent's early tool evolution behavior relied heavily on prompt policy and implicit heuristics. That produced useful behavior, but promotion/reuse decisions were not consistently represented as auditable runtime data.

This ADR established a control plane for automatic shaping/evolution that keeps solver cognition flexible while making promotion policy explicit.

Since drafting, MVP infrastructure has been implemented and validated across phased rollout work documented in [`docs/reports/adr-0023-phase-validation-report.md`](../reports/adr-0023-phase-validation-report.md).

## Decision

Adopt a first-class solver/evolution evidence model with reliability-gated lifecycle transitions.

### 1. Solver shape is explicit runtime data

Each dynamic call captures `solver_shape` with stable fields:

1. `stance`
2. `capability_summary`
3. `reuse_basis`
4. `contract_intent`
5. `promotion_intent`

Capture is observational and does not directly mutate domain semantics.

### 2. Promotion lifecycle is version-aware and policy-gated

Tool artifacts transition through:

1. `candidate`
2. `probation`
3. `durable`
4. `degraded`

State is tracked per artifact checksum/version, not just per tool name.

### 3. Promotion policy v1 is explicit

Current implemented policy contract (`solver_promotion_v1`) gates `probation -> durable` using:

1. minimum observation window: `min_calls: 10`, `min_sessions: 2`
2. `min_contract_pass_rate: 0.95`
3. `max_guardrail_retry_exhausted: 0`
4. `max_outcome_retry_exhausted: 0`
5. `max_wrong_boundary_count: 0`
6. `max_provenance_violations: 0`
7. `min_state_key_consistency_ratio: 0.5`
8. if role-profile observations exist: `min_role_profile_pass_rate: 0.99`

### 4. Shadow and enforcement are separately controlled

Runtime flags:

1. `solver_shape_capture_enabled`
2. `promotion_shadow_mode_enabled`
3. `promotion_enforcement_enabled`

Shadow decisions are always logged when shadow mode is enabled. Enforcement controls selection behavior.

### 5. Selector and prompt integrate lifecycle evidence

1. selector prefers non-degraded versions in order: durable -> probation -> candidate
2. `<known_tools>` prompt rendering includes lifecycle/policy/reliability hints
3. ranking biases durable up and degraded down

### 6. Governance and operations are first-class

Operator tooling and docs support scorecard inspection, decision inspection, and audited manual lifecycle overrides.

### 7. Composition with ADR 0024 and ADR 0025

1. ADR 0023 measures reliability and lifecycle fitness.
2. ADR 0024 adds semantic continuity/correctness pressure for role-style interfaces.
3. ADR 0025 governs awareness and authority boundaries for evolution actions.

## MVP Delivered (Implemented)

Delivered in Ruby runtime and docs:

1. solver-shape capture and observability fields
2. version-scoped scorecards and lifecycle metadata persistence
3. promotion shadow engine with policy versioning and rationale logging
4. enforcement-capable selector path with kill-switch
5. lifecycle-aware known-tool ranking/prompt hints
6. operator command surfaces for scorecards/decisions/lifecycle overrides
7. rollout/maintenance/governance documentation

Primary implementation and evidence references:

1. [`runtimes/ruby/lib/recurgent/call_state.rb`](../../runtimes/ruby/lib/recurgent/call_state.rb)
2. [`runtimes/ruby/lib/recurgent/artifact_selector.rb`](../../runtimes/ruby/lib/recurgent/artifact_selector.rb)
3. [`runtimes/ruby/lib/recurgent/tool_store.rb`](../../runtimes/ruby/lib/recurgent/tool_store.rb)
4. [`runtimes/ruby/lib/recurgent/known_tool_ranker.rb`](../../runtimes/ruby/lib/recurgent/known_tool_ranker.rb)
5. [`docs/reports/adr-0023-phase-validation-report.md`](../reports/adr-0023-phase-validation-report.md)

## Deferred / Post-MVP

Not fully implemented yet:

1. computed `false_promotion` / `false_hold` classification pipeline (ledger counters exist, automated classification loop is not complete)
2. capability-class threshold specialization engine (global defaults remain active)
3. domain-capability hardening (for example movie listings quality) which is intentionally outside this ADR's policy scope

## Status Quo Baseline

Baseline (pre-implementation phase 0, see report):

1. Full test suite passed (`238 examples, 0 failures`), but no solver-shape/lifecycle policy contract existed in runtime traces.
2. Calculator baseline scenario could be correct, but semantic quality drift was not encoded as lifecycle evidence.
3. Assistant scenarios showed truthful failures (`capability_unavailable`) for missing capabilities; no promotion policy lane existed to reason about evolving candidates.

## Expected Improvements

1. Solver-shape visibility improves from implicit prompt-only behavior to explicit per-call telemetry coverage (`solver_shape` + completeness fields).
2. Promotion decisions improve from opaque heuristics to explicit policy-versioned lifecycle decisions with rationale fields.
3. Artifact reuse safety improves via version-aware lifecycle states and deterministic fallback preference order.
4. Operational auditability improves via inspectable scorecards/decisions and explicit policy toggles.

## Non-Improvement Expectations

1. Runtime does not reinterpret domain `Outcome.ok` into semantic error by heuristic judgment (ADR 0017 remains intact).
2. This ADR does not introduce domain-specific quality heuristics (news/movies/recipes correctness stays outside policy contract).
3. This ADR does not grant autonomous policy mutation authority (ADR 0025 authority boundaries remain in force).

## Validation Signals

1. Tests: full Ruby suite remains green during rollout phases.
2. Traces/logs: presence and stability of `solver_shape*`, `lifecycle_*`, `promotion_*`, and artifact-selection lifecycle fields.
3. Scorecard evidence: version-scoped counters and policy-version snapshots persist per artifact checksum.
4. Observation window threshold for durable eligibility: at least 10 calls across at least 2 sessions.

## Rollback or Adjustment Triggers

1. Promotion enforcement causes material regression in stable scenarios -> disable `promotion_enforcement_enabled` and continue shadow-only calibration.
2. Candidate volatility causes repeated degradation churn -> tighten thresholds or hold at probation while collecting more evidence.
3. A capability class shows sustained misfit (>2x false-hold/false-promotion vs global baseline once classification is available) -> introduce class-specific thresholds only for that class.

## Scope

In scope:

1. solver-shape contract and telemetry
2. reliability-gated lifecycle policy for artifact versions
3. selector/prompt integration with lifecycle evidence
4. operational inspection and control surfaces

Out of scope:

1. domain-specific semantic grading
2. replacing delegated contract validation mechanisms
3. autonomous runtime policy mutation

## Consequences

### Positive

1. Promotion and reuse policy are explicit, measurable, and auditable.
2. Evolution decisions are traceable at the same granularity as runtime execution.
3. Reliability and semantic-correctness layers remain separable and composable.

### Tradeoffs

1. Additional metadata and policy complexity in runtime persistence surfaces.
2. More operational discipline needed for threshold tuning and rollout governance.
3. Reliability policy can surface semantic instability but does not solve it alone.

## Alternatives Considered

1. Keep solver shape implicit in prompt text only.
   - Rejected: weak auditability and weak policy determinism.
2. Hard-code rigid planner behavior in runtime.
   - Rejected: conflicts with Tool Builder autonomy and project tenets.
3. Promote on first success.
   - Rejected: insufficient reliability evidence and higher drift risk.

## Rollout Plan

Rollout phases from this ADR are complete as MVP in Ruby runtime:

1. schema and trace capture
2. version-scoped scorecards
3. shadow promotion engine
4. controlled enforcement path
5. prompt/selector integration
6. operations/governance surfaces

Follow-up work continues under separate plans/ADRs for:

1. semantic continuity contracts (ADR 0024)
2. awareness/authority substrate evolution (ADR 0025)
3. quality hardening of specific capability flows

## Guardrails

1. Promotion gates must not rewrite domain outcomes.
2. Policy versions and lifecycle decisions must be logged and inspectable.
3. Lifecycle transitions must be reversible via selector policy and operator controls.
4. Reliability policy measures stability; semantic correctness requires complementary contracts (ADR 0024 when applicable).

## Ubiquitous Language Additions

No new UL terms introduced beyond those already adopted through ADR 0023/0024/0025 updates in [`docs/ubiquitous-language.md`](../ubiquitous-language.md).
