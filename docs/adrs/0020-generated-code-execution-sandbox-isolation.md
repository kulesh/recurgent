# ADR 0020: Generated Code Execution Sandbox Isolation

- Status: proposed
- Date: 2026-02-16

## Context

Recent traces exposed a structural runtime flaw:

1. Generated/persisted code is executed via `eval(..., binding)` on the Agent execution context.
2. Tool code can define methods (`def fetch_headlines`) that escape the call and pollute later method lookup.
3. Polluted lookup can bypass normal dynamic-dispatch lanes (`method_missing` -> lifecycle/observability/contract validation), producing inconsistent delegation traces.
4. This failure is not a prompt-quality issue; it is execution-surface leakage.

Observed symptom class:

1. A call path appears to delegate and returns `Outcome.ok`.
2. Subsequent calls show missing depth-1 delegated traces for equivalent capability execution.
3. Behavior remains superficially successful while lifecycle invariants are violated.

This conflicts with project tenets:

1. Agent-first mental model: Tool behavior must flow through the runtime lifecycle.
2. Runtime ergonomics and clarity: execution boundaries should be explicit and reliable.
3. Tolerant interfaces by default: runtime should tolerate idiomatic generated Ruby without leaking side effects across calls.
4. Ubiquitous language: Tool Builder/Tool/Worker lanes must remain mechanically distinct in execution.

## Decision

Adopt per-attempt execution sandbox isolation for generated code.

### 1. Per-attempt sandbox receiver

Generated code executes against an ephemeral sandbox object per attempt, not directly on Agent binding.

The sandbox owns attempt-local runtime variables:

1. `context`
2. `args`
3. `kwargs`
4. `result`

The sandbox is discarded after attempt completion.

### 2. Forwarded execution API surface

Sandbox forwards only the supported runtime surface to Agent:

1. `tool(...)`
2. `delegate(...)`
3. `remember(...)`
4. `memory` (read access)
5. `Agent::Outcome` construction access

No implicit full-Agent `self` exposure is provided.

### 3. Preserve idiomatic generated Ruby

`def` remains allowed in generated code.

Method definitions become sandbox-local for that attempt and do not mutate Agent method space.

`result`/`return` semantics remain unchanged from caller perspective.

### 4. Explicit mutation guardrails remain enforced

Pre-execution guardrails continue rejecting direct class/module mutation patterns against runtime host objects (for example `class Agent`, `class << Agent`, `Module#class_eval` against Agent).

Such violations stay in recoverable validation lanes (ADR 0016), with bounded retry feedback.

### 5. Observability and lifecycle integrity

Sandbox execution is first-class in logs and preserves existing lifecycle invariants:

1. delegated call boundaries remain visible,
2. contract validation boundaries stay intact,
3. guardrail/execution/outcome repair lanes remain deterministic.

Rollout logs include `execution_receiver` (`legacy` | `sandbox`) so trace analysis can verify delegation-fidelity improvements before removing legacy execution.

## Scope

In scope:

1. runtime execution receiver change for generated code,
2. sandbox API forwarding contract,
3. regression coverage for method-leak prevention,
4. observability updates needed to verify sandbox path behavior.

Out of scope:

1. prompt redesign,
2. tool naming/decomposition policy changes,
3. model tiering or recursion primitives.

## Consequences

### Positive

1. Eliminates cross-call method pollution from generated code.
2. Restores deterministic dispatch through runtime lifecycle boundaries.
3. Keeps generated Ruby ergonomic (`def` supported) without global side effects.
4. Reduces hidden divergence between apparent success and lifecycle correctness.

### Tradeoffs

1. Structural runtime refactor around execution context.
2. Generated code that depended on broad Agent `self` surface will fail fast and require regeneration/repair.
3. Sandbox-forward surface must stay explicit and documented as runtime evolves.

## Alternatives Considered

1. Ban `def` in generated code.
   - Rejected: non-idiomatic Ruby restriction; addresses symptom, not execution-boundary cause.
2. Keep Agent binding and patch prompt warnings only.
   - Rejected: does not provide mechanical isolation; leakage remains possible.
3. Keep Agent binding and add post-hoc cleanup of leaked methods.
   - Rejected: brittle, incomplete, and order-dependent.
4. Expand host object allowlist broadly (`self` as Agent with more methods).
   - Rejected: increases accidental coupling and leakage risk.

## Rollout Plan

### Phase 1: Sandbox Runtime Primitive

1. Introduce internal sandbox object and execute generated code against sandbox receiver.
2. Keep call-local `context/args/kwargs/result` behavior consistent with current contract.
3. Emit `execution_receiver: legacy|sandbox` in call logs during rollout.

### Phase 2: Forwarded API Contract

1. Implement explicit forwarding of `tool/delegate/remember/memory`.
2. Add tests for allowed API calls through sandbox.

### Phase 3: Regression and Invariants

1. Add regression test for method-definition leakage (define in one call, ensure no cross-call host mutation).
2. Add trace-level test ensuring delegated depth-1 calls remain visible across repeated ask scenarios.

### Phase 4: Guardrail and Prompt Alignment

1. Ensure guardrail classification for host-mutation patterns remains recoverable where appropriate.
2. Keep prompt API references aligned with sandbox-forwarded surface only.

## Guardrails

1. Execution isolation must not bypass existing validation/repair lanes.
2. Sandbox must not expose arbitrary host internals.
3. Lifecycle logging must remain complete for both top-level and delegated calls.
4. Backward compatibility with leaked-method behavior is intentionally not preserved.

## Relationship to Existing ADRs

1. ADR 0016 governs validation-first retries and transactional guardrail recovery; this ADR fixes execution receiver integrity inside that lifecycle.
2. ADR 0014 contract validation remains the outcome boundary invariant.
3. ADR 0012 persistence/repair remains unchanged; persisted artifacts now execute in an isolated receiver.
4. ADR 0019 structured conversation-history access remains unchanged; `context[:conversation_history]` stays available through sandbox `context`.

## Open Questions

1. What is the minimal long-term forwarded API surface for sandboxed code?
2. When should `execution_receiver` logging drop `legacy` support and become sandbox-only?
3. Should sandbox enforce additional static restrictions beyond existing guardrail policy, or rely solely on current policy lanes?
