# ADR 0007: Runtime-Agnostic Contract Spec

- Status: accepted
- Date: 2026-02-13

## Context

Recurgent now targets multiple runtimes (Ruby and planned Lua). Without a shared behavioral contract, runtime implementations can drift in semantics even if names stay aligned.

## Decision

Define a versioned contract package under `specs/contract/`:

1. `agent-contract.md` for normative behavior requirements.
2. `programs.yaml` for abstract generated-program semantics.
3. `scenarios.yaml` for runtime-agnostic conformance scenarios.
4. `conformance.md` for runtime harness expectations.

Contract versions are isolated (`v1/`, future `v2/` for breaking changes).

## Consequences

### Positive

- Ruby and Lua can validate against identical behavioral expectations.
- Enables parity work without forcing shared runtime internals.
- Keeps ubiquitous language stable while implementations evolve.

### Tradeoffs

- Adds maintenance overhead for versioned contract artifacts.
- Requires runtime-specific harness mapping from semantic program ids to local generated code.

## Rejected Alternatives

1. Keep contracts only in prose docs.
- Rejected: too ambiguous for repeatable conformance checks.

2. Share one executable harness across runtimes.
- Rejected: introduces avoidable coupling and language-specific leakage.
