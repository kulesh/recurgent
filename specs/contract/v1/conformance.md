# Contract v1 Conformance Guide

This guide defines how a runtime validates against `Agent Contract v1`.

## Harness Requirements

Each runtime harness SHOULD:

1. Load `programs.yaml`, `scenarios.yaml`, and `tolerant-delegation-scenarios.yaml`.
2. Provide a deterministic provider stub that can:
   - return program implementations by `program_id`
   - return invalid payload fixtures (`invalid_nil`, `invalid_blank`)
   - return ordered sequences for retry scenarios
3. Execute each scenario in isolation.
4. Emit per-scenario pass/fail with error details.

Harness SHOULD also load:

- `tolerant-delegation-profile.md`

## Runtime Mapping Responsibility

`program_id` values are semantic, not code.  
Each runtime maps them to local generated program text:

- Ruby runtime: Ruby code snippets.
- Lua runtime: Lua code snippets.

The observable result MUST match scenario expectations.

## Minimum Pass Condition

A runtime is v1-conformant when all scenario ids in `scenarios.yaml` and `tolerant-delegation-scenarios.yaml` pass.

## Reporting Format (Recommended)

```json
{
  "runtime": "ruby",
  "contract_version": 1,
  "passed": 10,
  "failed": 0,
  "results": [
    { "id": "coordination.agent_for_constructs_live_instance", "status": "pass" }
  ]
}
```
