# ADR 0016: Validation-First Fresh Generation and Transactional Guardrail Recovery

- Status: proposed
- Date: 2026-02-15

## Context

Recent traces exposed a lifecycle gap in fresh generation (non-persisted path):

1. Guardrails correctly block invalid approaches (for example, singleton method mutation on delegated Tools).
2. The same guardrail failure currently terminates the call instead of guiding bounded regeneration.
3. Failed attempts can partially mutate `context` before the guardrail fires, polluting subsequent retries.
4. Existing repair flow (ADR 0012) applies to persisted artifacts after execution failure, not to fresh code before successful execution.

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
5. If execution fails: continue to existing execution-failure handling (including persisted-artifact repair paths from ADR 0012 where applicable).

This separates:

1. **validation failure before execution** from
2. **execution failure after validation**.

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

Guardrail recovery must not consume provider-invalid-output retry budget.

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

These signals feed out-of-band quality analysis without widening hot-path complexity.

## Scope

In scope:

1. validation-before-execution stage in fresh generation flow;
2. recoverable-vs-terminal guardrail classification;
3. transactional attempt isolation and commit-on-success semantics;
4. structured retry feedback prompt for recoverable guardrails;
5. typed exhaustion outcomes and observability fields.

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
   - post-exec implementation repair.
4. Tool Builder behavior improves from structured policy feedback.
5. Fewer false terminal failures for recoverable policy mistakes.
6. Repeated guardrail-retry exhaustion becomes adaptive failure pressure instead of invisible churn.

### Tradeoffs

1. Runtime complexity increases (state isolation + rollback mechanics).
2. Additional prompt tokens for retry feedback.
3. Requires clear classification boundaries to avoid noisy retries.
4. Snapshot/isolation implementation must be performant under larger contexts.

## Alternatives Considered

1. Keep guardrails as immediate terminal roadblocks
   - Rejected: blocks iterative self-correction and wastes recoverable attempts.
2. Relax guardrails to warnings only
   - Rejected: permits policy bypass and harms persistence/contract integrity.
3. Expand ADR 0012 instead of a new ADR
   - Rejected: ADR 0012 is persisted-artifact lifecycle; this decision governs fresh-generation validation lifecycle.
4. Retry without transaction isolation
   - Rejected: unsafe due to partial context pollution between attempts.

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
3. Add acceptance traces demonstrating convergence from first invalid attempt to valid second attempt.

## Guardrails

1. Runtime guardrails remain enforceable constraints, never optional warnings.
2. Recovery feedback must describe mechanism violations, not prescribe domain answers.
3. Rollback must be deterministic and auditable (`rollback_applied=true/false`).
4. Retries are bounded; no unbounded regeneration loops.
5. Terminal guardrails bypass retry and return typed outcomes immediately.
6. `guardrail_retry_exhausted` contributes to adaptive failure pressure for tool-health/evolution telemetry.

## Open Questions

1. Isolation implementation strategy:
   - v1 is full context snapshot/restore;
   - when should we promote to copy-on-write or mutation journaling based on measured overhead?
