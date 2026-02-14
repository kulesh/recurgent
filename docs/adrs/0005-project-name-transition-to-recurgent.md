# ADR 0005: Transition Product Naming from Actuator to Recurgent

- Status: accepted
- Date: 2026-02-13

## Context

Current name (`Actuator`) describes mechanism. Proposed name (`Recurgent`, Recursive Agent) better reflects delegation behavior and product direction.

A hard rename risks breaking users and fragmenting docs.

## Decision

Adopt hard-cut naming transition:

1. `Recurgent` is canonical project/runtime naming.
2. `Agent` is canonical operational object naming.
3. Remove `Actuator` naming from runtime, docs, examples, and tests in one coordinated phase.
4. Do not maintain compatibility aliases in core runtime.

## Consequences

### Positive

- Enables a clean product narrative shift with one canonical vocabulary.
- Ensures one canonical language for LLM and human collaborators.

### Tradeoffs

- Immediate breakage for any legacy usage.
- Requires atomically updated code/docs/tests to avoid inconsistency.

## Rejected Alternatives

1. Gradual alias-based transition.
- Rejected: dual naming introduces semantic drift and cognitive overhead.

2. No rename.
- Rejected: weak alignment with recursive-agent product intent.
