# Recurgent Implementation Plan

## Objective

Align the product language and API surface with LLM-native delegation workflows while preserving emergent domain behavior.

## Problem Statement

Current internals are strong, but public language (`identity`, `context`, metaprogramming-heavy framing) is not aligned with how LLMs naturally reason about delegation:

- role selection
- memory handoff
- tool delegation
- answer synthesis

The plan is to add a coordination-layer vocabulary that matches this mental model without sacrificing dynamic domain API emergence.

## Design Principles

1. Preserve emergent domain methods.
- Keep `method_missing` behavior as the domain surface.
- Do not predefine domain verbs like `cosine`, `solve`, `diagnose`.

2. Add explicit coordination primitives.
- Introduce stable orchestration methods (`for`, `remember`, `memory`, `delegate`).
- Coordination API should be predictable and testable.

3. Keep naming and runtime semantics aligned.
- `Recurgent` is the canonical project/runtime name.
- `Agent` is the canonical operational object for LLM usage (`Agent.for(...)`).

4. Separate naming from runtime semantics.
- Runtime behavior should not depend on branding terms.
- Coordination vocabulary should stay minimal to reduce semantic drift for LLM users.

5. Codify tolerant delegation semantics.
- Use tolerant interaction semantics as the canonical runtime path.
- Use outcome envelopes for multi-tool Tool Builder workflows.

## Solution Options

### Option A: Keep current API; update docs only
- Pros: zero implementation risk.
- Cons: does not improve LLM-native ergonomics; mismatch persists.

### Option B (Recommended): Hard rename + focused API
- Pros: clean slate.
- Pros: removes conceptual drift immediately and simplifies long-term language.
- Cons: breaks old code immediately.

### Option C: Additive facade + phased rename
- Add `Agent` facade and coordination API while keeping `Actuator` intact.
- Introduce `Recurgent` naming via docs/module aliasing first.
- Evaluate adoption, then decide deprecation timeline.

## Phased Plan

### Phase 0: Vocabulary and contract alignment (docs + ADRs)
- Publish ADRs for coordination surface and naming transition.
- Define ubiquitous language map in docs.
- Capture non-goals and compatibility promises.

### Phase 1: Coordination API facade
- Add `Agent` facade with:
  - `Agent.for(role, **opts)`
  - `#remember(**entries)`
  - `#memory`
  - `#delegate(role, **opts)`
- Keep dynamic domain method dispatch unchanged.

`ask(...)` is explicitly deferred. It may be added later after usage evidence.

### Phase 2: Tests and acceptance workflows
- Unit tests for coordination methods.
- Acceptance tests for LLM-delegation flows:
  - agent creates tool delegate
  - memory handoff and retrieval
  - domain method still emergent (`calculator.cosine(60)`)

### Phase 2.5: Tolerant delegation profile
- Define Tool Builder/Tool vocabulary and outcome envelope model.
- Add contract profile and scenarios for tolerant delegations.
- Remove strict/raise-only ambiguity from runtime-facing contracts.

### Phase 3: Naming transition (hard cut)
- Remove `Actuator` naming from runtime/docs/examples.
- Canonical names:
  - project/runtime: `Recurgent`
  - operational object: `Agent`
- Update gem/module/entrypoint naming accordingly.

### Phase 4: Lua parity plan
- Define runtime-agnostic spec for `Agent`, `role`, `memory`, `delegate`, and emergent domain methods.
- Use same spec as the contract for upcoming Lua implementation.

## Work Breakdown

1. Documentation
- Add ubiquitous language section to [`README.md`](../../README.md).
- Add migration guide under [`docs/`](..).
- Keep docs index and retrieval index updated.

2. API
- Implement `Agent` concrete class with `Agent.for(...)`.
- Keep dynamic domain runtime behavior unchanged.

3. Test coverage
- Unit tests for facade behavior.
- BDD acceptance scenarios for delegation orchestration.
- Contract scenarios for tolerant delegation behavior and synthesis continuity.

4. Observability
- Keep current log fields and add any facade-level metadata only if needed.

## Risks and Mitigations

1. Overly large fixed API causing LLM semantic drift.
- Mitigation: keep fixed coordination vocabulary minimal.

2. Drift between facade and core behavior.
- Mitigation: ensure facade delegates directly to core methods and add contract tests.

3. Hard-cut rename integration churn.
- Mitigation: execute rename atomically across code, tests, docs, and examples in one phase.

## Acceptance Criteria

1. LLM orchestration can be expressed in coordination vocabulary without losing dynamic domain API.
2. `Agent.for(...)` is canonical and documented.
3. Tests cover coordination primitives plus emergent domain behavior.
4. Documentation clearly explains coordination methods vs emergent domain methods.
5. Documentation and contracts define canonical tolerant delegation semantics.

## Decisions Captured

1. `Agent` is a concrete class.
2. Canonical constructor is `Agent.for(role, **opts)`.
3. `ask(...)` is deferred until usage evidence warrants it.
4. Rename is a hard cut: remove `Actuator` naming now.
5. Tool Builder/Tool language is canonical for multi-agent problem-solving flows.
6. Tolerant delegation interfaces are a codified design value.
