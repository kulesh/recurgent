# ADR 0018: ContextView and Recursive Context Exploration (V1)

- Status: proposed
- Date: 2026-02-16

## Context

Recurgent's current strengths are:

1. durable Tool identity and artifact evolution,
2. validation-first lifecycle and repair loops,
3. contract-governed delegation boundaries.

A remaining gap is long-context exploration inside a single capability shape.

Today, when a task requires inspecting large context, decomposition is possible but ergonomically blunt:

1. `delegate(...)` creates/uses another Tool boundary,
2. `Agent.for(...)` creates an explicit new role instance,
3. neither provides a first-class way to recurse over context slices while preserving one cognitive identity.

Recursive Language Models (RLMs) show value in recursive decomposition over context. Recurgent should borrow the mechanism while preserving its own differentiator: contracted Tool evolution with typed outcomes.

## Decision

Introduce a V1 recursive context exploration surface with two primitives:

1. `ContextView`
2. `recurse(...)`

### 1. `ContextView` (first-class context windowing)

Add a runtime-managed `ContextView` abstraction for bounded context access.

`ContextView` supports deterministic, composable operations such as:

1. `peek`
2. `slice`
3. `grep`
4. `partition`
5. `summarize`

`ContextView` is a read-focused exploration surface. Parent context mutation remains explicit at normal runtime boundaries.

### 2. `recurse(...)` (same-capability recursive subcall)

Add a runtime primitive conceptually shaped as:

```ruby
recurse(query:, context_ref:, depth: nil, metadata: {})
```

Semantics:

1. `recurse(...)` spawns a depth+1 subcall under the same role/capability intent.
2. The subcall receives a bounded context reference (`context_ref`) from `ContextView`.
3. The subcall returns typed `Outcome`; parent decides how to merge/use result.
4. Subcall state is isolated by existing attempt isolation semantics.

### 3. Distinction from existing primitives

`recurse(...)` is intentionally different from `delegate(...)` and `Agent.for(...)`.

1. `delegate(...)`
   - purpose: cross-tool composition with explicit contract boundary,
   - outcome: Tool creation/reuse and potential persistence evolution.
2. `Agent.for(...)`
   - purpose: explicit root/independent role instantiation.
3. `recurse(...)`
   - purpose: same-role recursive exploration of context,
   - not a Tool creation primitive,
   - not a separate role bootstrap primitive.

### 4. Contract and capability invariants

Recursive subcalls must preserve Recurgent invariants.

1. No capability escalation through recursion.
2. Recursion does not bypass delegated outcome validation.
3. Recursion does not bypass guardrail policy.
4. Recursion outputs remain typed outcomes and observable.

### 5. Observability requirements

Recursive execution must be trajectory-native in logs.

Each recursive event captures at least:

1. `recursion_id`
2. `parent_call_id`
3. `depth`
4. `context_ref`
5. `query`
6. `outcome_type`
7. `duration_ms`

This makes recursive reasoning auditable and diagnosable.

### 6. V1 scope boundaries

In scope for this ADR:

1. `ContextView` surface,
2. `recurse(...)` primitive,
3. runtime invariants and observability.

Explicitly out of scope for V1:

1. model tiering by depth,
2. Recursim integration and replay policy,
3. automatic recursion budget tuning.

## Scope

This ADR governs runtime API and lifecycle behavior for recursive context exploration.

It does not change:

1. artifact selection policy from ADR 0012,
2. validation-first guardrail recovery from ADR 0016,
3. contract-driven utility semantics from ADR 0017.

## Consequences

### Positive

1. Improves long-context decomposition ergonomics without forcing new Tool boundaries.
2. Enables recursive exploration while preserving Tool Builder/Tool/Worker language.
3. Maintains contract and guardrail discipline under recursion.
4. Produces better trajectory data for later optimization.

### Tradeoffs

1. Adds another coordination primitive that must be taught in prompt policy.
2. Requires clear guidance to avoid overusing recursion where direct execution is sufficient.
3. Increases observability payload volume.

## Alternatives Considered

1. Use only `delegate(...)` for recursion
   - rejected: conflates same-capability decomposition with cross-tool composition.
2. Use only `Agent.for(...)` for recursion
   - rejected: role bootstrap is too heavy for intra-capability recursive exploration.
3. Delay recursion until model tiering is designed
   - rejected: context exploration value is independent of tiering and can progress now.

## Rollout Plan

### Phase 1: Runtime surface

1. Introduce internal `ContextView` object and context-ref representation.
2. Add `recurse(...)` execution path with depth propagation.
3. Ensure typed outcome passthrough and isolation semantics.

### Phase 2: Policy and guardrails

1. Add prompt policy describing when to recurse vs do/delegate.
2. Add guardrails for malformed context refs and recursive misuse.
3. Keep depth/cost tuning minimal and defer model tiering.

### Phase 3: Observability

1. Emit recursion trajectory fields in logs.
2. Add diagnostics for recursion path quality.

## Guardrails

1. Recursion must not bypass outcome contract validation.
2. Recursion must not bypass lifecycle guardrails.
3. Recursion is bounded by existing runtime safety mechanisms; no unbounded loops.
4. Parent call remains owner of final side-effect claims and result assembly.

## Open Questions

1. Should `ContextView` expose only read operations in v1, or allow explicit staged writes?
2. What is the minimal canonical `context_ref` schema for stable replay/debuggability?
3. Which recursion misuse signals should be classified as recoverable vs terminal guardrails?
