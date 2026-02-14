# ADR 0003: Error Handling Contract

- Status: accepted
- Date: 2026-02-13

## Context

Current behavior often converts failures into opaque strings or hard exceptions, which weakens failure visibility and makes caller handling inconsistent in long delegation flows.

## Decision

Adopt a typed outcome contract for dynamic calls:

- Dynamic calls return `Agent::Outcome` with `status: :ok | :error`.
- Error outcomes carry typed `error_type` values (`provider`, `invalid_code`, `execution`, `timeout`, `budget_exceeded`).
- Runtime still records typed Ruby error classes (`ProviderError`, `ExecutionError`, etc.) in logs/debug metadata.
- Logging failures are non-fatal by default but can be surfaced in debug mode.
- `to_s` should remain safe and never raise unexpectedly in presentation contexts.

## Consequences

- Positive: failures become explicit, typed, and composable for Solver synthesis.
- Positive: callers handle one consistent return shape instead of exception branching.
- Tradeoff: callers/tests must adopt `Outcome` handling semantics.
