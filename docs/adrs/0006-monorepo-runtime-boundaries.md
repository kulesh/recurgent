# ADR 0006: Monorepo Runtime Boundaries

- Status: accepted
- Date: 2026-02-13

## Context

Recurgent is now explicitly multi-runtime (Ruby now, Lua planned). Keeping all runtime code at repository root increases coupling, makes cross-runtime expansion noisy, and blurs runtime-specific dependency/tooling boundaries.

## Decision

Adopt a runtime-partitioned monorepo layout:

1. Keep shared product and architecture documentation at repository root ([`docs/`](..), [`README.md`](../../README.md), ADRs).
2. Place each runtime implementation in `runtimes/<language>/`.
3. Keep runtime-specific tooling, tests, examples, and packaging metadata inside each runtime directory.
4. Preserve one ubiquitous language and contract across runtimes while allowing independent runtime release cadence.

## Consequences

### Positive

- Clean boundaries for dependencies, tests, and runtime-specific workflows.
- Lower risk of Ruby/Lua implementation details leaking into each other.
- Enables contract-parity development across runtimes.

### Tradeoffs

- Cross-runtime CI matrix becomes more complex.
- Some commands now require an explicit runtime directory (`cd runtimes/ruby`).

## Rejected Alternatives

1. Keep all runtime files at repository root.
- Rejected: scales poorly and creates ownership ambiguity as runtimes multiply.

2. Split into separate repositories per runtime.
- Rejected: duplicates docs/ADRs and increases coordination cost for contract alignment.
