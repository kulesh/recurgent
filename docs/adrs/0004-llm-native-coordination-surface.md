# ADR 0004: Add LLM-Native Coordination API Surface

- Status: accepted
- Date: 2026-02-13

## Context

The runtime supports emergent domain APIs through dynamic dispatch, but orchestration language is currently implementation-centric (`identity`, `context`) rather than delegation-centric (`role`, `memory`, `delegate`).

LLM agents benefit from stable coordination primitives, while domain behavior should remain emergent.

## Decision

Introduce an additive coordination-layer API with LLM-native nomenclature:

- `Agent.for(role, **opts)`
- `agent.remember(**entries)`
- `agent.memory`
- `agent.delegate(role, **opts)`

Preserve dynamic domain method behavior as-is via `method_missing`.

`ask(...)` is deferred pending usage evidence; it is not part of v1 coordination primitives.

## Consequences

### Positive

- Better cognitive alignment for LLM delegation workflows.
- Improves readability and consistency for orchestration code.
- Preserves open-ended domain API synthesis.

### Tradeoffs

- More public API surface to maintain.
- Potential confusion between coordination methods and emergent methods without strong docs.

## Rejected Alternatives

1. Docs-only rename with no API additions.
- Rejected: does not improve runtime ergonomics.

2. Replace emergent dispatch with fixed domain APIs.
- Rejected: breaks core product thesis.
