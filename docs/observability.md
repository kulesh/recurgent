# Observability and Mechanistic Interpretability

Recurgent emits JSONL call logs designed for runtime introspection across Ruby and Lua.

## Live Watcher

Use the shared watcher at repository root:

```bash
bin/recurgent-watch
```

Useful filters:

```bash
# Tail from beginning
bin/recurgent-watch --from-start

# Focus only failures
bin/recurgent-watch --status error

# Trace one Tool Builder flow
bin/recurgent-watch --trace <trace_id>

# Scope to a role/method pattern
bin/recurgent-watch --role "philosophy|assistant" --method "respond|delegate"
```

## Common Log Fields

Core fields (required by contract):

- `timestamp`
- `runtime`
- `role`
- `model`
- `method`
- `args`
- `kwargs`
- `code`
- `duration_ms`
- `generation_attempt`
- `outcome_status`
- `contract_source`

Cross-runtime traceability fields (recommended):

- `trace_id`
- `call_id`
- `parent_call_id`
- `depth`

Execution-path field:

- `execution_receiver` (`sandbox` for local generated execution, `worker` for dependency-backed worker execution)

Contract metadata fields (optional but recommended when present):

- `contract_purpose`
- `contract_deliverable`
- `contract_acceptance`
- `contract_failure_policy`

Lifecycle repair fields (recommended for fresh-path retries):

- `attempt_id`
- `attempt_stage` (`generated`, `validated`, `executed`, `rolled_back`)
- `validation_failure_type`
- `rollback_applied`
- `retry_feedback_injected`
- `guardrail_recovery_attempts`
- `execution_repair_attempts`
- `outcome_repair_attempts`
- `outcome_repair_triggered`
- `guardrail_retry_exhausted`
- `outcome_repair_retry_exhausted`

Failed-attempt diagnostics (internal-only):

- `latest_failure_stage` (`validation`, `execution`, `outcome_policy`)
- `latest_failure_class`
- `latest_failure_message` (bounded/truncated)
- `attempt_failures` (ordered array of per-attempt diagnostics):
  - `attempt_id`
  - `stage`
  - `error_class`
  - `error_message`
  - `timestamp`
  - `call_id`

These fields are for logs/artifacts and repair analysis only. User-facing boundary messages remain normalized by lifecycle policy.

## How to Read Delegation Trees

1. Group by `trace_id`.
2. Build tree edges via `parent_call_id -> call_id`.
3. Use `depth` for display indentation.
4. Use `outcome_status` and `outcome_error_type` to identify failure nodes and retry hotspots.

## Runtime Notes

- Ruby runtime currently emits the full recommended traceability fields.
- Lua runtime should emit the same keys to reuse the watcher unchanged.
