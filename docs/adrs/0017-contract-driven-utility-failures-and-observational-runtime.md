# ADR 0017: Contract-Driven Utility Failures and Observational Runtime Semantics

- Status: proposed
- Date: 2026-02-15

## Context

Recent runtime behavior exposed a philosophical and architectural mismatch:

1. A Tool returned `Outcome.ok` with self-signaled weak status (for example `success_no_parse` + empty list).
2. Runtime coercion converted that success into `Outcome.error(low_utility)` at boundary validation.
3. Calls became safer, but Tool behavior did not evolve: runtime compensated silently.

This conflicts with project tenets:

1. Agent-first mental model: Tool Builders and Tools should learn through explicit feedback loops.
2. Runtime ergonomics and clarity: runtime should enforce boundaries, not rewrite domain semantics.
3. Tolerant interfaces by default: runtime can normalize shape/key tolerance, but must not silently reinterpret success intent.
4. Ubiquitous language: Tool Builder forges contracts; Tools either succeed meaningfully or fail honestly.

Related decisions:

1. ADR 0014 enforces delegated `deliverable` shape at outcome boundaries.
2. ADR 0015 introduces `low_utility` and `wrong_tool_boundary` as typed referral/usefulness outcomes.
3. ADR 0012 provides persisted repair/regeneration once failures are explicit.

## Decision

Runtime semantics remain observational for utility quality; utility pressure must come from explicit contracts and telemetry, not status rewriting.

### 1. No Runtime Success->Error Coercion

Runtime MUST NOT convert `Outcome.ok` into `Outcome.error` purely from heuristic status/message inspection.

Allowed runtime transformations:

1. tolerant shape/key canonicalization (ADR 0014),
2. contract-shape violation mapping to typed `contract_violation`,
3. serialization/transport normalization.

Disallowed:

1. semantic reinterpretation of Tool-authored success into failure based on ad hoc status strings.

### 2. Utility Expectations Must Be Machine-Checkable Contract, Not Prose

Utility requirements that should fail inline must be represented in enforceable contract fields under `deliverable` constraints (not only free-form `acceptance` prose).

Examples of enforceable utility constraints (v1 direction):

1. array `min_items`,
2. object field non-empty constraints,
3. bounded required collection constraints on declared keys.

If constraint fails, runtime returns typed `contract_violation` through existing boundary mechanism.

### 3. Keep Tool-Authored Utility Vocabulary First-Class

Tools should be nudged to emit:

1. `Outcome.error(error_type: "low_utility", ...)` when output is structurally valid but not useful,
2. `Outcome.error(error_type: "wrong_tool_boundary", ...)` when task crosses capability boundaries.

These remain Tool-authored semantics, not runtime-authored rewrites.

### 4. Out-of-Band Pressure for Weak-Success Drift

When Tools repeatedly return weak-but-OK outputs:

1. preserve emitted outcome status,
2. record weak-success telemetry and user-correction signals,
3. apply evolution pressure in out-of-band maintenance/evaluation loops.

This preserves emergence while still driving improvement.

### 5. Fast Reliability and Emergence Can Coexist

Inline reliability stays deterministic via:

1. boundary validation,
2. fresh execution repair retries,
3. persisted artifact repair.

Emergence stays intact because semantic ownership remains with Tool output + contract evolution.

## Scope

In scope:

1. policy that runtime must not coerce utility semantics from success to error;
2. contract-driven approach for inline utility failures;
3. telemetry-driven approach for non-inline utility drift;
4. prompt guidance updates that prioritize Tool-authored typed outcomes.

Out of scope:

1. runtime-autonomous tool decomposition/splitting;
2. domain-specific heuristics for websites/sources;
3. replacing delegated boundary validation from ADR 0014.

## Consequences

### Positive

1. Tool behavior remains legible and accountable (no hidden semantic rewrite layer).
2. Repair/regeneration pressure flows through explicit typed failures.
3. Tool Builders are incentivized to forge stronger machine-checkable contracts.
4. Runtime remains a boundary enforcer and observer, not a compensating policy engine.

### Tradeoffs

1. Some weak successes may reach users until contracts or tools evolve.
2. Contract schema must evolve to express quality constraints without overfitting.
3. Out-of-band evaluation quality depends on telemetry signal quality.

## Alternatives Considered

1. Keep runtime heuristic coercion (`ok` -> `low_utility`)
   - Rejected: hides semantics from Tool, weakens emergent adaptation.
2. Enforce free-form `acceptance` text as executable policy
   - Rejected: ambiguous, non-deterministic, high risk of brittle parsing.
3. Out-of-band only (no inline contract utility constraints)
   - Rejected: too slow for high-frequency quality failures that should fail fast.

## Rollout Plan

### Phase 1: Remove Semantic Coercion

1. Remove success-status heuristic coercion in boundary validator.
2. Keep current tolerant shape canonicalization intact.
3. Add regression tests to ensure runtime does not rewrite Tool-authored success semantics.

### Phase 2: Enforceable Utility Constraints in `deliverable`

1. Extend `deliverable` validator with minimal machine-checkable utility constraints (v1).
2. Map violations to `contract_violation` with precise metadata (`mismatch`, expected vs actual).
3. Add acceptance tests using movie-style empty-result scenarios.

### Phase 3: Prompt/Contract Authoring Alignment

1. Update Tool Builder prompt guidance to encode quality expectations in enforceable `deliverable` constraints.
2. Keep `acceptance` as explanatory intent, not primary runtime enforcement.

### Phase 4: Out-of-Band Evolution Pressure

1. Record weak-success telemetry + `user_correction` signals.
2. Feed these into tool-health/cohesion views and evolution recommendations.
3. Prioritize Tool Builder re-forge/decomposition decisions from telemetry evidence.

## Guardrails

1. Runtime may canonicalize shape; runtime may not rewrite outcome intent.
2. Inline failures must be deterministic and machine-checkable.
3. Contract evolution must remain Tool Builder-driven.
4. Telemetry informs evolution; telemetry must not silently mutate semantics.

## Open Questions

1. Which minimal `deliverable` utility constraints provide highest leverage in v1 (`min_items`, non-empty keys, both)?
2. Should repeated weak-success + user-correction signals auto-increase regeneration priority, or only surface recommendations?
3. How should utility constraints balance strictness (fast failure) vs tolerance (open-world variability)?
