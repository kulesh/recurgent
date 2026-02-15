# Delegate vs Agent.for

Use both primitives, but for different intents.

Both primitives accept the same delegation contract fields (`purpose`, `deliverable`, `acceptance`, `failure_policy`).

## Decision Rule

1. Use `Agent.for(...)` when bootstrapping an independent agent from outside an existing Tool Builder flow.
2. Use `tool_builder.delegate(...)` when a Tool Builder summons a Tool during an active solve loop.

## Why `delegate` Exists

`delegate` preserves Tool Builder runtime contract by default (model, logging, retry policy, timeout, and related coordination settings).
That keeps Tool behavior inside one coherent solve session instead of creating ad hoc runtime islands.

## Concrete Scenarios

1. Philosophy symposium (`runtimes/ruby/examples/philosophy_debate.rb`)
- Tool Builder: symposium host.
- Tools: Stoic, Epicurean, Existentialist.
- Better with `delegate`: each philosopher should inherit the same runtime envelope for comparable outcomes and traceability.

2. Debate panel with persona branches (`runtimes/ruby/examples/debate.rb`)
- Tool Builder: panel host/panelist.
- Tools: persona-specific debaters (for example Dennis Ritchie branch).
- Better with `delegate`: avoids contract drift across nested delegation chains and makes budget/timeout controls enforceable.

## When `Agent.for` Is Better

1. Top-level script startup.
- Example: create the first Tool Builder in CLI/user code.

2. Independent agent sessions.
- Two agents with intentionally different runtime contracts should be started explicitly with separate `Agent.for(...)` calls.

## Anti-Pattern

Inside Tool Builder-generated code, repeatedly spawning Tools with raw `Agent.for(...)` and custom ad hoc options can fragment policy and observability.

Preferred approach:

- Tool Builder uses `delegate` for Tool work.
- Runtime-level `Delegation Budget` governs chain growth.
