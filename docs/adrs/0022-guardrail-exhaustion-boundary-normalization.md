# ADR 0022: Guardrail Exhaustion Boundary Normalization

- Status: proposed
- Date: 2026-02-16

## Context

Recent traces exposed a lifecycle gap at the user boundary:

1. Guardrail retries are correctly executed (ADR 0016).
2. When retries exhaust, raw internal guardrail diagnostics can leak to user-facing responses.
3. Internal messages are implementation details (policy strings, schema fragments, correction hints), not stable user-facing semantics.

This is a generic lifecycle issue. It is not specific to any one guardrail type:

1. provenance violations,
2. registry-shape violations,
3. singleton-method violations,
4. contract/validation guardrails,
5. future guardrails added over time.

This conflicts with project tenets:

1. Agent-first mental model: internal diagnostics should stay precise for Tool Builder/Tool evolution.
2. Tolerant interfaces by default: user-facing outcomes should be stable, typed, and capability-oriented.
3. Runtime ergonomics and clarity: internals should remain observable without becoming user API.
4. Ubiquitous language: lifecycle semantics should be generic, not category-specialized.

Related decisions:

1. ADR 0016 defines validation-first retries and recoverable guardrail recovery.
2. ADR 0017 preserves observational runtime semantics (no hidden semantic coercion).
3. ADR 0021 defines provenance-required success for external-data behavior as one specific guardrail.

## Decision

Adopt a generic boundary normalization policy for all guardrail retry-exhaustion outcomes.

### 1. Guardrail Violations Emit Structured Subtypes

All guardrail violations SHOULD include machine-readable subtype metadata (for example `missing_external_provenance`, `context_tools_shape_misuse`, `singleton_method_mutation`), in addition to human-readable message text.

Subtype metadata becomes first-class for:

1. retry correction prompts,
2. telemetry aggregation,
3. user-boundary normalization.

### 2. Top-Level Boundary Normalizes Exhausted Guardrails

When a top-level invocation exhausts recoverable guardrail retries, the surfaced user-facing outcome MUST be normalized to a stable typed error.

Normalization requirements:

1. no raw internal policy strings in user-facing `error_message`,
2. preserve retry exhaustion fact and class as metadata,
3. keep mapping generic across guardrail subtypes.

V1 message policy:

1. Use subtype-agnostic user-facing message text (for example: "This request couldn't be completed after multiple attempts.").
2. Keep subtype detail in metadata/logs only.
3. Defer subtype-aware user templates until evidence shows users need differentiated corrective guidance.

### 3. Internal Fidelity Is Preserved

Normalization is presentation at user boundary only.

Internal artifacts/logs/traces MUST retain full diagnostics:

1. guardrail class,
2. subtype,
3. original message,
4. correction hints,
5. retry counters and exhaustion metadata,
6. failed-attempt diagnostics (`attempt_failures`, `latest_failure_*`) captured by lifecycle telemetry.

Depth scope for v1:

1. Apply boundary normalization only at top-level (`depth == 0`).
2. Do not normalize depth-1+ tool outcomes; preserve raw typed errors for parent orchestration decisions.
3. Keep subtype signal intact for tool-level retries, alternates, and escalation.

### 4. No Category-Specific Lifecycle Lanes

Runtime MUST NOT introduce category-specific normalization lanes (for example external-data-only lifecycle treatment). Category-specific invariants (such as ADR 0021 provenance) remain as individual guardrails with subtype metadata.

### 5. Capability-Oriented Typed Outcomes

User-facing normalized errors should use stable typed vocabulary aligned to capabilities and lifecycle state (for example `guardrail_retry_exhausted`, optional subtype-aware user message templates), not implementation internals.

## Scope

In scope:

1. generic normalization of exhausted recoverable guardrails at top-level boundary,
2. structured subtype metadata for guardrail violations,
3. preserving internal diagnostics while stabilizing user-facing semantics.

Out of scope:

1. changing individual guardrail invariants (for example ADR 0021 provenance requirements),
2. domain-specific parser behavior or quality heuristics,
3. special-case runtime handlers by category/domain.

## Consequences

### Positive

1. User-facing errors become stable and trustworthy.
2. Guardrail implementation details remain internal while still fully observable.
3. New guardrails automatically benefit from boundary policy without special casing.
4. Lifecycle language stays generic and extensible.

### Tradeoffs

1. Requires explicit subtype tagging discipline in guardrail definitions.
2. Adds a boundary-mapping layer that must be maintained as guardrails evolve.
3. Some existing tests expecting raw messages will need updates.

## Alternatives Considered

1. Keep current behavior (raw internal messages can surface).
   - Rejected: unstable and leaks implementation detail.
2. Add category-specific normalizers (external-data-only, etc.).
   - Rejected: creates special lanes and weakens generic lifecycle model.
3. Hide all details from both users and telemetry.
   - Rejected: harms repair quality and out-of-band evolution.

## Rollout Plan

### Phase 1: Structured Subtypes

1. Ensure all current guardrails emit subtype metadata.
2. Add subtype fields to observability entries where missing.

### Phase 2: Boundary Normalization

1. Normalize top-level exhausted guardrail outcomes to stable user-facing typed failures.
2. Keep original diagnostics in outcome metadata/logs.

### Phase 3: Telemetry and Maintenance

1. Aggregate guardrail exhaustion by subtype and capability pattern.
2. Feed these signals into maintenance/evolution prioritization.

### Phase 4: Acceptance Traces

1. Validate at least two distinct guardrail subtypes in live traces.
2. Confirm user-facing outputs do not contain raw policy/schema internals.

## Guardrails

1. Boundary normalization is a presentation concern, not semantic success coercion (ADR 0017).
2. Retry lifecycle semantics remain unchanged (ADR 0016).
3. Individual invariants (for example ADR 0021 provenance) remain enforced as their own guardrails.

## Open Questions

1. What evidence threshold should trigger subtype-aware user templates in v2?
2. Should v2 expose limited user-action hints for selected subtypes without leaking internal policy text?
