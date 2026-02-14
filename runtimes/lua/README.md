# Recurgent Lua Runtime

This directory is reserved for the Lua implementation of Recurgent.

Planned contract parity with Ruby runtime:

- `Agent.for(role, **opts)` constructor equivalent, including contract fields (`purpose`, `deliverable`, `acceptance`, `failure_policy`)
- emergent domain methods via dynamic dispatch
- coordination primitives: `remember`, `memory`, `delegate`
- structured provider output -> executable code path

Canonical contract source:

- `../../specs/contract/v1/agent-contract.md`
- `../../specs/contract/v1/scenarios.yaml`

Shared observability tooling:

- `../../bin/recurgent-watch` consumes runtime JSONL logs when Lua emits the common log fields.
- `../../docs/observability.md` documents required/recommended keys.
