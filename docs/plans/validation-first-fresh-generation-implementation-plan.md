# Validation-First Fresh Generation Implementation Plan

## Objective

Implement ADR 0016 so fresh-generated calls can recover from guardrail violations safely and deterministically instead of failing immediately.

The plan enforces:

1. validation before execution,
2. recoverable guardrail retries with bounded budget,
3. attempt-local transactionality (commit on success, rollback on failure),
4. strict guardrails that shape iteration rather than terminate it,
5. fresh-path retriable `Outcome.error` repairs owned by runtime orchestration.

## Alignment with Project Tenets

1. Agent-first mental model:
   - guardrails guide the Tool Builder toward valid approaches through structured feedback.
2. Tolerant interfaces by default:
   - recoverable policy violations retry; terminal failures still return typed outcomes.
3. Runtime ergonomics before premature constraints:
   - explicit lifecycle stages, explicit failure classes, explicit budgets.
4. Ubiquitous language:
   - Tool Builder iterates, Tools execute via policy-compliant interfaces, Workers stay unchanged.

## Scope

In scope:

1. Fresh-path pre-execution validation stage.
2. Guardrail classification (`recoverable_guardrail`, `terminal_guardrail`) with default-recoverable policy.
3. Transactional attempt isolation (snapshot/restore in v1).
4. Dedicated `guardrail_recovery_budget` separate from provider generation retries.
5. Structured retry feedback contract for recoverable guardrail failures.
6. Typed exhaustion outcome (`guardrail_retry_exhausted`).
7. Fresh-path retriable-outcome repair lane with dedicated `fresh_outcome_repair_budget`.
8. Typed exhaustion outcome for outcome-repair budget exhaustion (`outcome_repair_retry_exhausted`).
9. Observability/telemetry fields for attempt lifecycle and rollback.
10. Integration with adaptive failure pressure signals.

Out of scope:

1. Persisted artifact repair flow redesign (ADR 0012 remains source of truth).
2. Runtime-autonomous tool decomposition.
3. Lua parity.
4. Performance optimization beyond correctness-first snapshot/restore in v1.

## Current State Snapshot

Already implemented:

1. Guardrails enforce tool-registry integrity (for example, block singleton method mutation on Agent instances).
2. Fresh calls retry provider/schema failures only.
3. Persisted artifacts support repair/regeneration flow.
4. Typed outcomes and observability are already first-class.

Current gaps:

1. No pre-exec validation lifecycle stage in fresh path.
2. No retry loop for recoverable runtime guardrail violations.
3. Failed fresh attempts can partially mutate `context`/registry before failure.
4. No dedicated budget separation between provider-generation retries and guardrail recovery retries.
5. No runtime-owned repair loop for retriable fresh-path `Outcome.error` returns.
6. No typed exhaustion outcome for repeated retriable-outcome repairs.

## Design Constraints

1. Default guardrail classification is recoverable unless explicitly terminal.
2. Terminal guardrails are exception-only:
   - missing credentials,
   - unavailable external dependency/service,
   - unsupported runtime capability.
3. Retries are always bounded.
4. Rollback must be deterministic and observable.
5. Recovery feedback describes mechanism violations, not domain answers.
6. v1 chooses correctness/debuggability over optimization.

## Delivery Strategy

Deliver in six phases. Each phase is independently testable.

### Phase 0: Contracts, Taxonomy, and Baselines

Goals:

1. Finalize failure taxonomy and lifecycle vocabulary.
2. Capture baseline traces for before/after comparison.

Implementation:

1. Define guardrail classes:
   - `recoverable_guardrail`
   - `terminal_guardrail`
2. Define terminal allowlist (explicitly configured).
3. Define typed exhaustion error contract:
   - `error_type: "guardrail_retry_exhausted"`
4. Capture baseline traces from known failure scenario:
   - movie tool-forging path with singleton-method violation.

Suggested files:

1. `docs/adrs/0016-validation-first-fresh-generation-and-transactional-guardrail-recovery.md`
2. `docs/baselines/<date>/...`

Exit criteria:

1. Taxonomy and exhaustion contract are documented.
2. Baseline traces are archived for regression review.

### Phase 1: Fresh Lifecycle Stage Split (Generate -> Validate -> Execute)

Goals:

1. Make pre-exec validation a first-class stage.
2. Keep existing execution/repair behavior intact for non-validation failures.

Implementation:

1. Add explicit pre-exec validation hook in fresh path after code generation and before eval/worker execution.
2. Validation returns structured result:
   - pass,
   - recoverable guardrail failure,
   - terminal guardrail failure.
3. Preserve current provider retry logic unchanged.

Suggested files:

1. `runtimes/ruby/lib/recurgent/call_execution.rb`
2. `runtimes/ruby/lib/recurgent.rb`
3. `runtimes/ruby/lib/recurgent/call_state.rb`

Exit criteria:

1. Fresh call logs show stage transitions (`generated`, `validated`, `executed`).
2. Existing non-guardrail successful behavior is unchanged.

### Phase 2: Transactional Attempt Isolation (v1 Snapshot/Restore)

Goals:

1. Prevent failed attempts from polluting subsequent retries.
2. Commit state only from successful attempts.

Implementation:

1. Add attempt wrapper that snapshots mutable state before validation/execution:
   - `context`,
   - tool registry metadata,
   - other mutable per-call runtime state.
2. On recoverable guardrail failure:
   - restore snapshot,
   - mark rollback in call state.
3. On success:
   - commit attempt state.
4. On terminal failure:
   - restore snapshot and return typed outcome.

Suggested files:

1. `runtimes/ruby/lib/recurgent/call_execution.rb`
2. `runtimes/ruby/lib/recurgent/call_state.rb`
3. `runtimes/ruby/lib/recurgent/tool_store.rb` (if additional snapshot boundaries are needed)

Exit criteria:

1. Failed-attempt context mutations never persist across retries.
2. Tool-registry metadata from failed attempts does not leak into final state.

### Phase 3: Recoverable Guardrail Retry Loop + Structured Feedback

Goals:

1. Turn recoverable guardrail trips into bounded iterative recovery.
2. Preserve strict guardrail enforcement.

Implementation:

1. Add dedicated `guardrail_recovery_budget` (default 1-2), separate from provider generation retries.
2. On recoverable guardrail failure:
   - inject structured retry feedback into next generation prompt:
     - `violation_type`
     - `violation_message`
     - `violation_location`
     - `required_correction`
     - `remaining_guardrail_budget`
   - regenerate code and re-validate.
3. On budget exhaustion:
   - return typed error `guardrail_retry_exhausted`,
   - include last-violation metadata.

Suggested files:

1. `runtimes/ruby/lib/recurgent.rb`
2. `runtimes/ruby/lib/recurgent/call_execution.rb`
3. `runtimes/ruby/lib/recurgent/prompting.rb`
4. `runtimes/ruby/lib/recurgent/outcome.rb`

Exit criteria:

1. Recoverable guardrail violation triggers retry without returning immediate terminal error.
2. Exhaustion path returns typed `guardrail_retry_exhausted` outcome.

### Phase 4: Observability and Adaptive Pressure Integration

Goals:

1. Make lifecycle state and rollback behavior inspectable in traces.
2. Feed repeated guardrail exhaustion into adaptive-failure pressure.

Implementation:

1. Add log fields:
   - `attempt_id`
   - `attempt_stage`
   - `validation_failure_type`
   - `rollback_applied`
   - `retry_feedback_injected`
   - `guardrail_recovery_attempts`
   - `guardrail_retry_exhausted`
   - `outcome_repair_attempts`
   - `outcome_repair_triggered`
   - `outcome_repair_retry_exhausted`
2. Persist guardrail exhaustion counts in artifact/tool metrics.
3. Classify repeated guardrail exhaustion as adaptive pressure input.
4. Classify repeated outcome-repair exhaustion as adaptive pressure input.

Suggested files:

1. `runtimes/ruby/lib/recurgent/observability.rb`
2. `runtimes/ruby/lib/recurgent/call_state.rb`
3. `runtimes/ruby/lib/recurgent/artifact_metrics.rb`
4. `runtimes/ruby/lib/recurgent/pattern_memory_store.rb` (if event schema extension is needed)

Exit criteria:

1. Logs fully reconstruct per-attempt lifecycle.
2. Repeated guardrail and outcome-repair exhaustion appear in health metrics.

### Phase 5: Fresh Outcome-Repair Lane (Post-Execution Error Outcomes)

Goals:

1. Recover from retriable fresh-path `Outcome.error` results without requiring thrown exceptions.
2. Keep retry ownership in runtime, not generated Tool code.

Implementation:

1. After successful execution, evaluate returned `Outcome`.
2. If `outcome.error? && outcome.retriable`:
   - classify failure (`extrinsic`, `adaptive`, `intrinsic`),
   - for non-extrinsic failures, rollback and regenerate using structured outcome-failure feedback.
3. Use dedicated `fresh_outcome_repair_budget` (v1 default: 1) independent of other budgets.
4. On exhaustion, emit typed non-retriable outcome `outcome_repair_retry_exhausted` with last-failure metadata.

Suggested files:

1. `runtimes/ruby/lib/recurgent/fresh_generation.rb`
2. `runtimes/ruby/lib/recurgent/fresh_outcome_repair.rb`
3. `runtimes/ruby/lib/recurgent/guardrail_policy.rb`
4. `runtimes/ruby/lib/recurgent/guardrail_outcome_feedback.rb`
5. `runtimes/ruby/lib/recurgent/call_state.rb`

Exit criteria:

1. Swallowed exceptions wrapped in retriable `Outcome.error` trigger one runtime-managed retry.
2. Non-retriable or extrinsic errors do not trigger this lane.
3. Exhaustion path returns typed `outcome_repair_retry_exhausted`.

### Phase 6: Hardening, Prompt Calibration, and Rollout

Goals:

1. Stabilize behavior under real assistant traces.
2. Ensure guardrails stay strict while retries remain useful.

Implementation:

1. Add/adjust prompt hints:
   - explicit prohibition patterns,
   - explicit recovery expectations in retry prompts.
2. Calibrate classification map:
   - default recoverable,
   - explicit terminal allowlist.
3. Validate with acceptance trace scenarios:
   - singleton-method failure then recovery,
   - retriable outcome-error failure then recovery,
   - terminal missing-capability case (no retry),
   - mixed provider retry + guardrail retry sequence.

Suggested files:

1. `runtimes/ruby/lib/recurgent/prompting.rb`
2. `runtimes/ruby/spec/acceptance/recurgent_acceptance_spec.rb`
3. `docs/observability.md`

Exit criteria:

1. Recoverable guardrail cases converge without context pollution.
2. Terminal cases fail fast with typed outcomes.
3. No regression on existing persistence/repair behavior.

## Runtime Contract Updates (v1)

### Validation Failure Classification

```json
{
  "validation_result": "failed",
  "guardrail_class": "recoverable_guardrail",
  "violation_type": "tool_registry_violation",
  "violation_message": "Defining singleton methods on Agent instances is not supported",
  "required_correction": "Use tool(\"name\") or delegate(\"name\", ...) and call dynamic methods; do not mutate Agent objects."
}
```

### Outcome-Repair Exhaustion Outcome

```json
{
  "status": "error",
  "error_type": "outcome_repair_retry_exhausted",
  "error_message": "Retriable outcome-error repairs exhausted for personal assistant.ask",
  "retriable": false,
  "metadata": {
    "outcome_repair_attempts": 1,
    "last_error_type": "fetch_failed"
  }
}
```

### Exhaustion Outcome

```json
{
  "status": "error",
  "error_type": "guardrail_retry_exhausted",
  "error_message": "Recoverable guardrail retries exhausted for personal assistant.ask",
  "retriable": false,
  "metadata": {
    "guardrail_recovery_attempts": 2,
    "last_violation_type": "tool_registry_violation"
  }
}
```

## Test Strategy

### Unit Tests

1. Guardrail classifier:
   - default recoverable behavior,
   - explicit terminal mapping.
2. Retry budget accounting:
   - generation, guardrail, and outcome-repair budgets are independent.
3. Snapshot/restore:
   - rollback restores context and registry exactly.
4. Exhaustion outcome shape:
   - typed errors with metadata for both guardrail and outcome-repair exhaustion.

### Integration Tests

1. Recoverable violation loop:
   - first attempt violates guardrail,
   - second attempt corrected,
   - final outcome succeeds,
   - no leaked first-attempt mutations.
2. Terminal violation:
   - no recovery retry,
   - immediate typed outcome.
3. Mixed failure-class sequence:
   - provider invalid output retries,
   - then guardrail recovery retries,
   - then outcome-error recovery retry,
   - budgets tracked independently.

### Acceptance Tests

1. Movie-tool scenario from live trace:
   - first generated approach uses singleton mutation (simulated fixture),
   - runtime retries with correction feedback,
   - final flow uses compliant `delegate/tool` path.
2. Regression suite:
   - Google/Yahoo/NYT sequence still works.
3. Negative safety:
   - attempts that fail guardrail do not create durable tool entries.

## Rollout Plan

1. Ship Phase 1-2 behind an internal runtime switch:
   - enable stage split and rollback first.
2. Enable Phase 3 retry loop next:
   - start with `guardrail_recovery_budget=1`.
3. Enable Phase 5 outcome-repair loop next:
   - start with `fresh_outcome_repair_budget=1`.
4. Expand observability and adaptive pressure.
5. Increase budgets only after trace validation.

## Risks and Mitigations

1. Risk: snapshot overhead on large contexts.
   - Mitigation: v1 snapshot/restore plus latency metrics; optimize only if needed.
2. Risk: noisy retry loops.
   - Mitigation: strict bounded budgets + terminal/extrinsic gating.
3. Risk: over-classifying terminal failures as recoverable.
   - Mitigation: explicit terminal map with tests and periodic review.
4. Risk: prompt bloat from retry feedback.
   - Mitigation: concise structured feedback fields only.
5. Risk: swallowed exceptions silently bypass execution-exception lane.
   - Mitigation: post-execution outcome evaluation lane with retriable gating.

## Completion Checklist

1. [ ] Pre-exec validation stage implemented in fresh path.
2. [ ] Recoverable/terminal classification implemented with default recoverable policy.
3. [ ] Transactional attempt isolation (snapshot/restore) implemented and verified.
4. [ ] Dedicated guardrail recovery budget implemented.
5. [ ] Structured retry feedback integrated into regeneration prompts.
6. [ ] `guardrail_retry_exhausted` typed outcome implemented.
7. [ ] Observability fields emitted and documented.
8. [ ] Adaptive pressure wiring includes repeated guardrail exhaustion.
9. [ ] Fresh-path retriable outcome repair lane implemented with dedicated budget.
10. [ ] `outcome_repair_retry_exhausted` typed outcome implemented and logged.
11. [ ] Adaptive pressure wiring includes repeated outcome-repair exhaustion.
9. [ ] Acceptance traces demonstrate recovery without leaked state.
