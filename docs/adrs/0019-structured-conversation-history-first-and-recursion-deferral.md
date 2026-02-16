# ADR 0019: Structured Conversation History First, Recursive Primitives Deferred

- Status: proposed
- Date: 2026-02-16

## Context

Recurgent needs better long-context handling, but the project is still in a nascent phase.

A broad recursion surface (`ContextView`, `recurse(...)`) was captured in ADR 0018 as a forward-looking direction. However, introducing new coordination primitives now creates risk:

1. additional policy surface before we have trace evidence,
2. more decision volatility (`do` vs `delegate` vs `recurse`) without empirical grounding,
3. premature runtime abstraction that may not match how Tool Builders naturally decompose tasks.

The immediate need is simpler: give Tool Builders direct, structured access to prior interaction history and observe what decomposition behaviors emerge.

## Decision

Adopt a data-first step before new recursion APIs.

### 1. Structured conversation history as plain runtime data

Expose `context[:conversation_history]` as a structured Ruby array of records available directly to generated code.

V1 record shape should be explicit and stable enough for programmatic use:

1. `call_id`
2. `timestamp`
3. `speaker` (`user|agent|tool`)
4. `method_name`
5. `args`
6. `kwargs`
7. `outcome_summary`

The shape remains tolerant to additive fields.

### 2. Prompt policy update

Prompting must explicitly tell Tool Builders:

1. conversation history is available at `context[:conversation_history]`,
2. it is structured data intended for direct read/query/filter operations,
3. direct code access should be preferred over speculative helper abstractions.

### 3. No new recursion primitive in this phase

Do not introduce `ContextView` or `recurse(...)` yet.

`delegate(...)` and `Agent.for(...)` semantics remain unchanged.

### 4. Evidence-gathering instrumentation

Add observability signals to evaluate whether recursion primitives are justified later.

At minimum, capture:

1. whether generated code accessed `context[:conversation_history]`,
2. history query patterns used (filter/map/slice style summaries),
3. repeated boilerplate patterns indicating missing runtime affordances,
4. repeated same-role decomposition attempts that currently route through delegation.

## Scope

In scope:

1. conversation-history schema and runtime population,
2. prompt guidance for direct history access,
3. observability fields for evidence gathering.

Out of scope:

1. `ContextView` class,
2. `recurse(...)` primitive,
3. model tiering,
4. Recursim integration work.

## Consequences

### Positive

1. Minimal surface-area change with immediate utility.
2. Preserves emergence-first philosophy by observing agent behavior before introducing abstractions.
3. Reduces premature architectural commitments.

### Tradeoffs

1. Some history-processing code may be duplicated in generated programs.
2. Deep-context ergonomics may remain rough until evidence-driven abstractions are introduced.

## Alternatives Considered

1. Implement ADR 0018 immediately.
   - rejected for now: broad primitive set before evidence from real traces.
2. Keep history unstructured and rely on model memory.
   - rejected: weak for deterministic introspection and code-level manipulation.

## Rollout Plan

### Phase 1: History Schema

1. define canonical `context[:conversation_history]` record shape,
2. populate records on each call lifecycle.

### Phase 2: Prompting and Usage

1. add explicit prompt guidance about history access,
2. verify generated code can read and use structured history.

### Phase 3: Evidence Collection

1. emit observability fields for history-access patterns,
2. gather traces to decide if `ContextView`/`recurse(...)` is warranted.

## Guardrails

1. History exposure must preserve existing capability boundaries.
2. History records should avoid storing non-serializable payloads.
3. Additive schema changes must remain backward-tolerant.

## Relationship to ADR 0018

ADR 0018 remains a forward-looking proposal.

This ADR sequences the work: first observe behavior with structured history access, then decide whether recursive primitives are justified.

## Open Questions

1. Which history fields are mandatory in v1 versus optional diagnostic enrichments?
2. Should history retention be bounded by count, time window, or token-estimated footprint?
3. What objective threshold (pattern frequency) should trigger revisiting ADR 0018 for implementation?
