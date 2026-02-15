# Tolerant Delegation Profile (v1)

Status: active profile for Agent Contract v1

This profile defines canonical delegation behavior for multi-delegation workflows.

## 1. Scope

Applies to dynamic delegation/runtime calls (API shape runtime-specific).

## 2. Requirements

1. A failed Tool delegation MUST produce an `Outcome` with `status: :error` (or runtime-equivalent).
2. Delegation failure MUST NOT force immediate termination of the containing Tool Builder workflow.
3. Error outcome MUST carry typed classification at minimum:
   - `provider`
   - `invalid_code`
   - `execution`
   - `timeout` (when runtime supports bounded provider timeout)
   - `budget_exceeded` (when runtime supports delegation budget limits)
4. Successful delegations MUST produce `status: :ok` and include returned value.
5. Tool Builder MUST be able to continue subsequent delegations after one failure.
6. Logging/debug metadata SHOULD preserve per-delegation outcome traceability.

## 3. Non-Goals

- This profile does not prescribe one concrete API name.

## 4. Conformance

Conformance is defined by passing scenarios in `tolerant-delegation-scenarios.yaml`.
