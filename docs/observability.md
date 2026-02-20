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

Solver-shape fields (recommended for decision introspection):

- `solver_shape`
- `solver_shape_complete`
- `solver_shape_stance`
- `solver_shape_promotion_intent`

Promotion lifecycle fields (recommended for shadow/enforcement audits):

- `promotion_policy_version`
- `lifecycle_state` (`candidate`, `probation`, `durable`, `degraded`)
- `lifecycle_decision` (`promote`, `continue_probation`, `degrade`, `hold`)
- `promotion_decision_rationale`
- `promotion_shadow_mode`
- `promotion_enforced`
- `artifact_selected_checksum`
- `artifact_selected_lifecycle_state`

Context-scope pressure fields (recommended for ADR 0025 evidence gate):

- `namespace_key_collision_count` (pairwise sibling-method key collisions for active role)
- `namespace_multi_lifetime_key_count` (keys observed with more than one inferred lifetime profile)
- `namespace_continuity_violation_count` (count of continuity drifts linked to namespace ambiguity)

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

## Operator Queries

Use [`bin/recurgent-tools`](../bin/recurgent-tools) to inspect scorecards and decision traces for specific interfaces:

```bash
# View version-scoped scorecards + lifecycle summary for one role/method
bin/recurgent-tools scorecards "news_aggregator" "get_headlines"

# View recent promotion decisions from shadow ledger
bin/recurgent-tools decisions "news_aggregator" "get_headlines" --limit 20

# View namespace-pressure metrics for one role
bin/recurgent-tools namespace-pressure "calculator"
```

## Context Scope Evidence Gate (ADR 0025 Phase 5)

Use namespace-pressure metrics to decide whether a follow-up context-scope migration ADR is justified.

Trigger a follow-up ADR when, for the same role, all conditions hold over a meaningful sample window:

1. `namespace_key_collision_count >= 3` across at least 2 distinct sessions.
2. `namespace_multi_lifetime_key_count >= 1` sustained across at least 2 sessions.
3. `namespace_continuity_violation_count >= 2` and increasing over recent calls.

If these thresholds are not met, document a no-trigger decision and continue collecting telemetry.
