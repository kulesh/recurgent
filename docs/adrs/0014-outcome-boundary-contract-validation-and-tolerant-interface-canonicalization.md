# ADR 0014: Outcome Boundary Contract Validation and Tolerant Interface Canonicalization

- Status: proposed
- Date: 2026-02-15

## Context

Recent end-to-end traces (Google News -> Yahoo News -> New York Times) showed a milestone and a gap:

1. Tool forging worked (`web_fetcher`, `rss_parser`).
2. Cacheability gating worked (`ask` regenerated, tools reused).
3. Pattern memory worked (`<recent_patterns>` appeared by call 3).
4. Cross-session persistence worked (artifact hits occurred).

The failures were integration quality failures at tool boundaries:

1. `web_fetcher` produced an Outcome value with `:body`, while caller code read `"body"` only.
2. `web_fetcher` interface drifted (`fetch_url` and `fetch`) across calls.
3. `rss_parser.parse(nil)` returned `[]` (silent success) instead of a typed error.

This is not a prompt-quality problem. This is a runtime contract enforcement problem:

- producer and consumer were both locally valid,
- but boundary shape was never validated against the delegation contract.

Project philosophy requires:

1. Agent-first mental model (Agent chooses design and delegation).
2. Tolerant interfaces by default.
3. Runtime ergonomics and clarity before premature constraints.
4. Ubiquitous language aligned to Agent thinking.

## Decision

Introduce runtime-enforced contract checks at the delegated Outcome boundary while preserving tolerant interface behavior.

### 1. Enforce Delegation Contract on Successful Outcomes

When a delegated call returns `Outcome.ok`, runtime validates `outcome.value` against the delegated contract `deliverable` (when present).

If value violates contract shape:

1. Convert to typed error outcome (`error_type: "contract_violation"`).
2. Preserve original role/method linkage for observability.
3. Treat as adaptive/intrinsic failure class (not silent success).

This moves contract truth from prompt suggestion to runtime guarantee.

### 2. Tolerant Object-Key Validation Semantics

Contract validation for object deliverables treats symbol and string keys as equivalent.

Example:

- Required key `"body"` is satisfied by either `value["body"]` or `value[:body]`.

This preserves tolerant interfaces while still enforcing shape.

### 3. Canonical Tool Interface Metadata in Registry

Tool registry entries will include interface metadata beyond purpose/deliverable:

1. canonical methods (`methods`).
2. optional aliases (`aliases`), when discovered.

Known-tools prompt injection should include canonical method hints so the Tool Builder prefers existing interfaces instead of inventing near-duplicate method names.

This improves reuse while keeping Agent-first naming evolution.

Example shape in prompt/registry metadata:

```yaml
web_fetcher:
  purpose: "fetch and extract content from URLs"
  methods: ["fetch_url"]
```

### 4. Contracted Tool Precondition Discipline

For contracted tools, invalid required inputs (for example, parser input is `nil`/empty) must return typed errors rather than successful empty payloads.

This is the same boundary principle in the input direction:

1. fail early,
2. fail typed,
3. avoid silent semantic corruption.

## Scope

In scope:

1. Delegated success-path contract validation against `deliverable`.
2. Tolerant key-equivalence handling in validator.
3. Registry metadata extension for canonical methods.
4. Prompt exposure of method metadata in `<known_tools>`.
5. Observability fields for contract validation outcomes.

Out of scope:

1. Hard method freeze that blocks all novel method generation.
2. Runtime-autonomous tool design decisions.
3. Full JSON Schema engine for v1 deliverable validation.

## Consequences

### Positive

1. Eliminates silent producer/consumer shape mismatches.
2. Preserves tolerant interfaces (symbol/string key flexibility) without sacrificing correctness.
3. Reduces API drift (`fetch_url` vs `fetch`) by surfacing canonical interface.
4. Turns contract from advisory prompt text into executable boundary behavior.
5. Improves artifact health signal quality (failures become observable and classifiable).

### Tradeoffs

1. Slight runtime overhead for contract validation on delegated successes.
2. Requires explicit deliverable shape quality; weak contracts produce weak validation.
3. Method metadata curation may need tie-break rules when aliases compete.

## Alternatives Considered

1. Prompt-only discipline ("remember to read both symbol and string keys")
   - Rejected: non-deterministic and regressible under context pressure.
2. Strict key normalization (force all hashes to string keys)
   - Rejected: less idiomatic Ruby ergonomics; conflicts with tolerant interface goal.
3. Disable tool reuse when any mismatch occurs
   - Rejected: penalizes persistence architecture instead of enforcing correct boundaries.
4. Accept silent empty-success behavior for parser-like tools
   - Rejected: hides boundary faults and propagates false state.

## Rollout Plan

### Phase 1: Boundary Validator

1. Add delegated-outcome validator for v1 deliverables:
   - object type + required keys,
   - array type checks where declared.
2. Implement symbol/string key-equivalence for required key checks.
3. Map violations to `Outcome.error(error_type: "contract_violation")`.
4. Include violation metadata for repairability:
   - `expected_shape`,
   - `actual_shape`,
   - `expected_keys`,
   - `actual_keys`,
   - `mismatch`.

### Phase 2: Interface Metadata

1. Extend tool registry entries with `methods` and optional `aliases`.
2. Capture canonical method names from stable successful calls.
3. Render method hints in `<known_tools>` prompt block.

### Phase 3: Precondition Hardening

1. Add contracted-tool precondition guidance to prompt + tests.
2. Ensure parser-like tools return typed error on nil/empty required input.
3. Add acceptance coverage for boundary mismatch scenarios.

## Guardrails

1. Runtime validator is a guardrail, not a replacement for Agent reasoning.
2. Validation must remain tolerant where domain permits (symbol/string equivalence).
3. Contract enforcement applies at delegated boundaries; non-delegated local values remain unconstrained.
4. Errors must be typed and observable; no silent downgrade to empty success.

## Open Questions

1. Should method metadata track argument-shape hints in v1 or names only?
   - Decision for v1: names only.
   - Rationale: method names are low-cost and usually self-documenting (`fetch_url`); argument-shape hints deferred to v2 unless traces show repeated argument-contract failures.
2. Should alias promotion be automatic (after repeated use) or manual via Tool Builder?
   - Decision: Tool Builder-driven consolidation.
   - Rationale: automatic runtime promotion would violate agent-first design; runtime may emit an observation signal when overlapping methods are detected.
3. Which deliverable shape features (nested required, scalar constraints) are worth adding in v2?
