# ADR 0001: Core Dispatch via method_missing

- Status: accepted
- Date: 2026-02-13

## Context

Agent needs a minimal runtime surface where unknown operations can be interpreted at call time by an LLM. We want a single dispatch hook that captures positional and keyword args while preserving object identity.

## Decision

Use Ruby `method_missing` as the core dispatch mechanism:

- Setter-style methods (`foo=`) are handled directly and persist to `@context`.
- Non-setter methods route through prompt construction, provider generation, and code execution.
- `respond_to_missing?` is implemented so introspection follows the dynamic contract.

## Consequences

- Positive: one clear entry point, small architecture, idiomatic Ruby metaprogramming.
- Positive: uniform handling for broad method vocabulary without predeclared API.
- Tradeoff: behavior is runtime-defined and depends on provider responses.
