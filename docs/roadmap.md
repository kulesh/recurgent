# Roadmap

## Near Term

1. Stabilize Ruby runtime contract harness aligned with [`specs/contract/v1`](../specs/contract/v1).
2. Expand deterministic acceptance scenarios for tolerant delegation behavior.
3. Tighten release automation and publishing flow.

## Mid Term

1. Implement Lua runtime with parity against [`specs/contract/v1`](../specs/contract/v1).
2. Add contract conformance runner tooling shared across runtimes.
3. Improve observability around outcome/error classification trends.
4. Add generated-code caching layer to reduce repeated provider calls for equivalent role/method/input shapes.

## Long Term

1. Multi-runtime compatibility guarantees with explicit version support windows.
2. Broader provider ecosystem support without changing core Agent contract.
3. Add persistent generated-code storage so agent behavior can accumulate and evolve across sessions.
