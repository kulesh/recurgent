# Agent Contract v1

Status: active  
Applies to: all Recurgent runtimes

## 1. Scope

This contract defines required observable behavior for the `Agent` object model:

- coordination primitives
- emergent method dispatch
- typed outcome boundaries
- logging contract fields

This contract does not standardize model quality or generated-code style.

## 2. Normative Terms

The keywords MUST, SHOULD, and MAY are normative.

## 3. Core Object Model

1. Runtimes MUST expose an operational object named `Agent`.
2. Runtimes MUST expose a canonical constructor equivalent to `Agent.for(role, **opts)`.
3. `Agent.for` MUST return a new live `Agent` instance with the provided role.

## 4. Coordination Primitives

1. `remember(**entries)` MUST write each entry into agent runtime context and return the same agent instance.
2. `runtime_context` MUST expose the current mutable runtime context map for that instance.
3. `delegate(role, **opts)` MUST return a new agent for the given role.
4. `delegate` MUST inherit runtime settings from parent unless overridden in `opts`.

## 5. Dynamic Dispatch

1. Setter-like calls (`name=`) MUST write directly to runtime context key `name`.
2. Setter-like calls MUST bypass provider code generation.
3. Non-setter missing methods MUST route through provider generation + execution.
4. Generated execution context MUST support:
   - persistent runtime context access
   - positional args
   - keyword args (or runtime-equivalent named args)
   - recursive agent creation/delegation

## 6. Introspection Semantics

1. `respond_to?` (or runtime-equivalent) MUST report true for setter-like names.
2. It MUST report true for runtime-context-backed readers after assignment.
3. It MUST report false for unknown dynamic methods not yet memory-backed.

## 7. Error Contract

1. Dynamic calls MUST return an `Outcome` envelope (or runtime-equivalent) with `status: ok|error`.
2. Provider generation failures MUST map to `Outcome(status: :error, error_type: "provider")`.
3. Invalid provider payload (nil/empty generated program) MUST map to `error_type: "invalid_code"`.
4. Generated program execution failures MUST map to `error_type: "execution"`.
5. Implementations SHOULD map timeout failures to `error_type: "timeout"` when bounded timeout is configured.
6. Implementations SHOULD map delegation-limit failures to `error_type: "budget_exceeded"` when delegation budgets are enabled.
7. Implementations MUST support configurable provider retry attempts.

## 8. Logging Contract

When logging is enabled, each dynamic call MUST emit one log entry containing:

- timestamp
- runtime
- role
- model/runtime model id
- method
- args
- kwargs (or runtime-equivalent named args representation)
- generated program/code
- duration
- generation_attempt
- outcome_status (`ok` | `error`)
- contract_source (`none` | `hash` | `fields` | `merged`)

When debug logging is enabled, entry MUST additionally include:

- system prompt/instructions
- user prompt/request
- runtime context snapshot after execution attempt

Logging failures MUST NOT break user-facing execution flow.

For cross-runtime delegation observability, runtimes SHOULD include:

- trace_id (stable across one Tool Builder flow)
- call_id (unique per dynamic call)
- parent_call_id (for call tree reconstruction)
- depth (delegation/call depth)

## 9. Conformance

Conformance is defined by passing all scenarios in `scenarios.yaml` using the abstract programs in `programs.yaml`.
