# Failed-Attempt Exception Telemetry Implementation Plan

- Status: draft
- Date: 2026-02-16
- Scope: ADR 0016 augmentation (internal lifecycle observability only)

## Goal

Persist precise failed-attempt diagnostics for fresh-call retries so repaired calls remain diagnosable after success.

Primary outcome:

1. When a call succeeds on attempt N>1, logs/artifacts still include what failed on attempts 1..N-1.

Non-goals:

1. No change to user-facing error text or boundary normalization semantics (ADR 0022 unchanged).
2. No category-specific behavior for provenance/external data.

## Design Summary

Add internal telemetry fields to fresh-call lifecycle state and emit them on completion:

1. `attempt_failures[]` (append-only, ordered).
2. `latest_failure_stage`, `latest_failure_class`, `latest_failure_message`.

Each failure record captures:

1. `attempt_id`
2. `stage` (`validation`, `execution`, `outcome_policy`)
3. `error_class`
4. `error_message` (truncated)
5. `timestamp` (UTC ISO8601)
6. `call_id`

## Phase 0: Schema and Limits

1. Define constants:
   - `MAX_FAILURE_MESSAGE_LENGTH` (default 400 chars)
   - `MAX_ATTEMPT_FAILURES_RECORDED` (default 8 entries per call)
2. Define canonical stage values in one place:
   - `validation`
   - `execution`
   - `outcome_policy`
3. Add helper normalizers:
   - `_truncate_failure_message(text)`
   - `_append_attempt_failure!(state:, attempt_id:, stage:, error:, call_context:)`

Acceptance:

1. Message truncation is deterministic and UTF-8 safe.
2. Unknown stages are rejected or normalized explicitly.

## Phase 1: Runtime State Wiring

1. Extend call state struct/default in `runtimes/ruby/lib/recurgent/call_state.rb`:
   - `attempt_failures`
   - `latest_failure_stage`
   - `latest_failure_class`
   - `latest_failure_message`
2. Initialize `attempt_failures` to `[]` per call.
3. Ensure fresh-attempt resets do not erase accumulated prior-attempt failures for the same call.

Acceptance:

1. Single-attempt success leaves `attempt_failures=[]`.
2. Repaired call retains prior failure records when attempt 2 succeeds.

## Phase 2: Capture Failure Events

Capture failures at all three lifecycle stages:

1. Validation failures (policy/syntax/guardrail recoverable path).
2. Execution failures (exceptions that trigger execution repair).
3. Outcome-policy failures (outcome-repair trigger path).

Touchpoints (expected):

1. `runtimes/ruby/lib/recurgent/fresh_generation.rb`
2. `runtimes/ruby/lib/recurgent/guardrail_policy.rb`
3. `runtimes/ruby/lib/recurgent/fresh_outcome_repair.rb`
4. `runtimes/ruby/lib/recurgent/call_execution.rb` (ensure/final aggregation path)

Rules:

1. Append failure before retry/regeneration.
2. Never overwrite previous entries; only append and update `latest_failure_*`.
3. Record same-attempt multi-failure events as separate entries.

Acceptance:

1. `execution_repair_attempts=1` implies at least one `attempt_failures` entry with stage `execution`.
2. `retry_feedback_injected=true` and validation retry implies stage `validation` record exists.

## Phase 3: Log and Artifact Emission

1. Add fields to log entry mapping in:
   - `runtimes/ruby/lib/recurgent/observability_attempt_fields.rb`
2. Ensure top-level JSONL includes:
   - `attempt_failures`
   - `latest_failure_*`
3. Enrich artifact generation history metadata on regenerate/repair triggers with:
   - `trigger_error_class`
   - `trigger_error_message` (truncated)
   - `trigger_stage`
   - `trigger_attempt_id`

Acceptance:

1. Repaired successful calls emit both success outcome and failed-attempt diagnostics.
2. Artifact history entries for regenerated code include trigger diagnostics.

## Phase 4: Tests

Add/extend specs in `runtimes/ruby/spec/recurgent_spec.rb`:

1. Validation-first retry test:
   - provoke recoverable guardrail violation on attempt 1;
   - assert `attempt_failures[0].stage == "validation"`.
2. Execution repair test:
   - attempt 1 raises runtime exception, attempt 2 succeeds;
   - assert:
     - `execution_repair_attempts == 1`
     - `attempt_failures` includes stage `execution`
     - `latest_failure_*` matches execution failure.
3. Outcome-policy repair test:
   - trigger `outcome_repair_attempts`;
   - assert stage `outcome_policy` appears in `attempt_failures`.
4. Truncation test:
   - long error message is truncated to configured limit.
5. Boundary safety test:
   - user-facing top-level normalized message remains generic (no raw internal error leak).

## Phase 5: Docs and Trace Verification

1. Update `docs/observability.md` examples with `attempt_failures` fields.
2. Capture one fresh repaired trace and include a short snippet in docs (or baseline note).
3. Verify `bin/recurgent-watch` remains functional with new fields.

Acceptance:

1. New fields are documented and visible in live logs.
2. Existing watcher filters do not break.

## Rollout

1. Ship as additive fields (backward compatible for log consumers).
2. Keep defaults conservative:
   - bounded message length,
   - bounded failure list size.
3. No feature flag required unless logs are consumed by strict external parsers.

## Risks and Mitigations

1. Risk: noisy/oversized logs.
   - Mitigation: truncation + max-entry cap.
2. Risk: accidental user-facing leakage.
   - Mitigation: keep emission in internal log/artifact paths only; preserve ADR 0022 boundary behavior.
3. Risk: inconsistent stage attribution.
   - Mitigation: central stage constants + tests per lane.
