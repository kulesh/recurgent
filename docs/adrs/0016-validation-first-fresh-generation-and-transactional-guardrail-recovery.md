# ADR 0016: Validation-First Fresh Generation and Transactional Guardrail Recovery

- Status: proposed
- Date: 2026-02-15

## Context

Recent traces exposed a lifecycle gap in fresh generation (non-persisted path):

1. Guardrails correctly block invalid approaches (for example, singleton method mutation on delegated Tools).
2. The same guardrail failure currently terminates the call instead of guiding bounded regeneration.
3. Failed attempts can partially mutate `context` before the guardrail fires, polluting subsequent retries.
4. Existing repair flow (ADR 0012) applies to persisted artifacts after execution failure, not to fresh code before successful execution.
5. Generated code can swallow runtime exceptions and return retriable `Outcome.error`, which currently bypasses fresh-path retry/repair lanes.
6. When fresh execution is repaired successfully, the log often preserves only counters (`execution_repair_attempts`) but not the failed-attempt exception message/class that triggered repair.

This creates a mismatch with project tenets:

1. Agent-first mental model: guardrails should shape model behavior, not only reject it.
2. Tolerant interfaces by default: failures should be informative and recoverable when feasible.
3. Runtime ergonomics before premature constraints: deterministic lifecycle stages should be explicit.
4. Ubiquitous language aligned to Agent cognition: Tool Builders should get iterative feedback loops, not hard stops, for recoverable policy violations.

## Decision

Introduce a validation-first fresh-generation lifecycle with transactional attempt isolation and recoverable guardrail retries.

### 1. Fresh Path Lifecycle Stages

For fresh generation calls, runtime flow becomes:

1. Generate program.
2. Pre-execution validation (syntax + policy/guardrail checks).
3. If recoverable validation fails:
   - rollback attempt-local mutations,
   - append structured failure feedback to retry prompt,
   - regenerate with bounded retry budget.
4. If validation passes: execute program.
5. If execution raises: continue to existing execution-failure handling.
6. If execution returns retriable `Outcome.error` (including swallowed exceptions wrapped as typed errors):
   - classify failure (`extrinsic`, `adaptive`, `intrinsic`),
   - if class is non-extrinsic and budget remains, rollback and regenerate with structured outcome-failure feedback,
   - otherwise return the outcome unchanged.
7. If outcome-repair budget is exhausted for eligible retriable outcomes:
   - return typed non-retriable outcome (`outcome_repair_retry_exhausted`) with last-outcome metadata.

This separates:

1. **validation failure before execution** from
2. **execution exception after validation** from
3. **retriable error outcomes after execution**.

### 2. Guardrail Classification Model

Guardrails are classified by recovery semantics:

1. `recoverable_guardrail`
   - Invalid approach can be rewritten in the same call.
   - Example: prohibited singleton mutation on Agent/Tool object.
2. `terminal_guardrail`
   - Retry cannot succeed without external changes (policy, credentials, unavailable capability).
   - Immediate typed outcome.

Default classification policy:

1. Default to `recoverable_guardrail` unless explicitly classified as terminal.
2. Terminal is exception-only and reserved for genuinely non-recoverable conditions:
   - missing credentials/secrets,
   - unavailable external dependency/service,
   - capability not supported by runtime policy.

Fresh-call retries apply only to `recoverable_guardrail`.

### 3. Transactional Attempt Isolation

Each fresh-generation attempt executes in an isolated mutable state:

1. Attempt-local `context` view.
2. Attempt-local tool-registry mutations.
3. Attempt-local telemetry staging.

Commit policy:

1. Commit staged state only when attempt validates and executes successfully.
2. On recoverable failure, rollback all staged mutations before retry.
3. On terminal failure/exhausted budget, return typed error with no partial state commit.

This makes retries safe rather than cumulative.

### 4. Structured Recovery Feedback Contract

When a recoverable guardrail fails, runtime injects structured retry feedback:

1. `violation_type`
2. `violation_message`
3. `violation_location` (when available)
4. `required_correction` (concise policy-preserving rewrite instruction)
5. `attempt_number` and `remaining_budget`

The prompt does not prescribe domain logic; it only constrains invalid mechanism use.

### 5. Bounded Retry Budget and Typed Exhaustion Outcome

Use separate budgets for independent failure classes:

1. `generation_retry_budget` (existing provider/schema generation retries),
2. `guardrail_recovery_budget` (new recoverable-guardrail regeneration retries; v1 default: 1-2 attempts).
3. `fresh_outcome_repair_budget` (new retriable-outcome regeneration retries on fresh path; v1 default: 1 attempt).

Guardrail recovery and outcome repair must not consume provider-invalid-output retry budget.

If all attempts fail recoverable validation:

1. return typed non-retriable outcome (`guardrail_retry_exhausted`),
2. include last violation metadata for introspection and out-of-band evolution.

### 6. Observability and Evolution Signals

Extend logs and metrics with fresh-lifecycle fields:

1. `attempt_id`
2. `attempt_stage` (`generated`, `validated`, `executed`, `rolled_back`)
3. `validation_failure_type`
4. `rollback_applied`
5. `retry_feedback_injected`
6. `guardrail_recovery_attempts`
7. `guardrail_retry_exhausted`
8. `outcome_repair_attempts`
9. `outcome_repair_triggered`
10. `outcome_repair_retry_exhausted`
11. `latest_failure_stage` (`validation`, `execution`, `outcome_policy`)
12. `latest_failure_class`
13. `latest_failure_message` (bounded/truncated)
14. `attempt_failures` (ordered per-attempt internal diagnostics)

### 7. Failed-Attempt Exception Telemetry (Internal-Only)

When a fresh call requires retry/repair, runtime MUST persist structured failed-attempt diagnostics for introspection and evolution pressure:

1. `attempt_failures[]` entries capture:
   - `attempt_id`
   - `stage` (`validation`, `execution`, `outcome_policy`)
   - `error_class`
   - `error_message` (truncated)
   - `timestamp`
   - `call_id`
2. `latest_failure_*` summary mirrors the most recent `attempt_failures` entry for fast filtering.
3. These diagnostics are internal-only:
   - available in logs/artifact metadata,
   - never surfaced directly to top-level user messages,
   - compatible with ADR 0022 boundary normalization.
4. Telemetry capture must be append-only within a call attempt sequence and deterministic across retries.

These signals feed out-of-band quality analysis without widening hot-path complexity.

## Scope

In scope:

1. validation-before-execution stage in fresh generation flow;
2. recoverable-vs-terminal guardrail classification;
3. transactional attempt isolation and commit-on-success semantics;
4. structured retry feedback prompt for recoverable guardrails;
5. fresh-path retriable-outcome repair lane with bounded budget;
6. typed exhaustion outcomes and observability fields;
7. failed-attempt exception telemetry (`attempt_failures`, `latest_failure_*`) for repaired fresh calls.

Out of scope:

1. changing persisted artifact repair policy from ADR 0012;
2. runtime-autonomous tool decomposition/refactoring;
3. domain-specific scraping heuristics;
4. model-specific prompt optimization unrelated to lifecycle state machine.

## Consequences

### Positive

1. Guardrails remain strict while becoming iterative guidance.
2. Retry safety improves due to rollback of failed-attempt mutations.
3. Fresh and persisted paths form one coherent lifecycle:
   - pre-exec validation recovery,
   - post-exec exception recovery,
   - post-exec retriable-outcome recovery.
4. Tool Builder behavior improves from structured policy feedback.
5. Fewer false terminal failures for recoverable policy mistakes.
6. Repeated guardrail-retry exhaustion becomes adaptive failure pressure instead of invisible churn.
7. Swallowed exceptions wrapped by Tool code no longer bypass runtime repair behavior.
8. Runtime failures that trigger successful repair remain diagnosable after the fact.

### Tradeoffs

1. Runtime complexity increases (state isolation + rollback mechanics).
2. Additional prompt tokens for retry feedback.
3. Requires clear classification boundaries to avoid noisy retries.
4. Snapshot/isolation implementation must be performant under larger contexts.
5. Additional retry lane requires careful budget calibration to avoid latency inflation.
6. Failure-message persistence requires bounded-size hygiene to avoid noisy logs.

## Alternatives Considered

1. Keep guardrails as immediate terminal roadblocks
   - Rejected: blocks iterative self-correction and wastes recoverable attempts.
2. Relax guardrails to warnings only
   - Rejected: permits policy bypass and harms persistence/contract integrity.
3. Expand ADR 0012 instead of a new ADR
   - Rejected: ADR 0012 is persisted-artifact lifecycle; this decision governs fresh-generation validation lifecycle.
4. Retry without transaction isolation
   - Rejected: unsafe due to partial context pollution between attempts.
5. Make Tool code self-orchestrate retries after returning `Outcome.error`
   - Rejected: violates runtime-owned lifecycle management and increases generated-code volatility.

## Rollout Plan

### Phase 1: Lifecycle Skeleton

1. Introduce explicit pre-execution validation stage in fresh path.
2. Add guardrail classification primitives (`recoverable`, `terminal`).
3. Add initial observability fields for stage transitions.

### Phase 2: Transactional Attempt Isolation

1. Execute fresh attempts in isolated mutable state.
2. v1 isolation strategy: full context snapshot/restore per attempt (correctness and debuggability first).
3. Commit-on-success; rollback-on-recoverable-failure.
4. Add tests proving no context/tool-registry pollution across failed attempts.

### Phase 3: Recoverable Guardrail Retry Loop

1. Add structured retry feedback payload for recoverable guardrail failures.
2. Re-run generation within dedicated `guardrail_recovery_budget`.
3. Emit `guardrail_retry_exhausted` typed outcome when budget is exhausted.

### Phase 4: Integration and Calibration

1. Integrate metrics into out-of-band analysis.
2. Tune recoverable/terminal classification thresholds.
3. Tune fresh outcome repair budget and eligibility thresholds (retriable + non-extrinsic only).
4. Add acceptance traces demonstrating convergence from first invalid attempt to valid second attempt.

### Phase 5: Failed-Attempt Telemetry Completion

1. Persist `attempt_failures` and `latest_failure_*` on fresh-call completion (including successful repaired calls).
2. Mirror failure trigger metadata into artifact generation history when regeneration occurs.
3. Add tests proving repaired calls retain first-attempt failure diagnostics with timestamp and stage.

## Guardrails

1. Runtime guardrails remain enforceable constraints, never optional warnings.
2. Recovery feedback must describe mechanism violations, not prescribe domain answers.
3. Rollback must be deterministic and auditable (`rollback_applied=true/false`).
4. Retries are bounded; no unbounded regeneration loops.
5. Terminal guardrails bypass retry and return typed outcomes immediately.
6. `guardrail_retry_exhausted` contributes to adaptive failure pressure for tool-health/evolution telemetry.
7. `outcome_repair_retry_exhausted` contributes to adaptive failure pressure for tool-health/evolution telemetry.
8. Failed-attempt diagnostics remain internal; user-boundary surfaces stay normalized per ADR 0022.

## Open Questions

1. Isolation implementation strategy:
   - v1 is full context snapshot/restore;
   - when should we promote to copy-on-write or mutation journaling based on measured overhead?
