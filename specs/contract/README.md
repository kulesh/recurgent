# Recurgent Contract Specs

This directory defines runtime-agnostic behavior contracts for Recurgent `Agent`.

Purpose:

- Keep one canonical behavioral contract across runtimes.
- Let each runtime (Ruby, Lua) implement local mechanics while preserving identical semantics.
- Make parity testable before and during Lua implementation.

## Layout

```text
specs/contract/
  README.md
  v1/
    agent-contract.md    # normative behavioral contract
    programs.yaml        # abstract generated-program semantics
    scenarios.yaml       # runtime-agnostic test scenarios
    tolerant-delegation-profile.md    # tolerant delegation profile
    tolerant-delegation-scenarios.yaml  # tolerant profile scenarios
    recurgent-log-entry.schema.json    # machine-readable schema for one JSONL log entry
    recurgent-log-stream.schema.json   # schema for jq-slurped JSONL stream arrays
    conformance.md       # harness guidance for runtime implementations
```

## How Runtimes Use This

Each runtime should implement a local contract harness that:

1. Loads `v1/scenarios.yaml` and `v1/tolerant-delegation-scenarios.yaml`.
2. Maps `program_id` values to runtime-local generated code (Ruby or Lua).
3. Executes scenarios against that runtime's `Agent`.
4. Reports pass/fail per scenario id.

## Versioning

- `v1/` is the current baseline.
- New incompatible contract changes require a new version directory (`v2/`).
- Runtime implementations should explicitly declare which contract version they pass.
