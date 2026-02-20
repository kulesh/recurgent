# Generated Code Execution Sandbox Isolation Implementation Plan

## Objective

Implement ADR 0020 by isolating generated-code execution to a per-attempt sandbox receiver so generated method definitions cannot leak into Agent method space.

Target outcomes:

1. Generated `def ...` remains idiomatic and local to one attempt.
2. Dynamic dispatch lifecycle integrity is preserved (`method_missing` lanes, delegation traces, contract boundaries).
3. Existing runtime tenets remain intact: Agent-first, tolerant interfaces, ergonomic runtime surfaces.

## Alignment with Project Tenets

1. Agent-first mental model:
   - Tool Builder/Tool behavior must flow through runtime lanes, not accidental host mutation.
2. Tolerant interfaces by default:
   - keep ergonomic Ruby generation (`def`, helper methods) while constraining side effects to attempt scope.
3. Runtime ergonomics and clarity before premature constraints:
   - fix execution surface, not prompt around the symptom.
4. Ubiquitous language:
   - Tool Builders forge, Tools execute, Workers run code; runtime keeps those boundaries observable.

## Scope

In scope:

1. Per-attempt sandbox receiver for local `eval` execution path.
2. Explicit forwarded API surface (`tool`, `delegate`, `remember`, `memory`, `Agent::Outcome` access via constant scope).
3. Lifecycle/observability updates to expose execution receiver.
4. Regression coverage for cross-call method leakage.
5. Trace validation for delegation fidelity on repeated assistant scenarios.

Out of scope:

1. Prompt strategy redesign.
2. Recursion primitives (`ContextView`/`recurse`).
3. Artifact selection policy redesign.
4. Domain-specific tool robustness changes (news parsing, etc.).

## Current State and Problem Statement

Current behavior:

1. `_execute_code` runs generated code on Agent binding.
2. Generated `def` can persist beyond the call.
3. Persisted artifacts with method definitions can silently alter later lookup behavior.

Observed impact:

1. Missing delegated depth-1 log entries for calls that appear delegated.
2. Apparent `Outcome.ok` while lifecycle invariants are violated.
3. Hard-to-debug volatility because execution path diverges from intended runtime lane.

## Design Constraints

1. Keep `def` allowed in generated code.
2. No silent broad `self` exposure to full Agent internals.
3. Maintain compatibility with ADR 0016 retry/rollback lifecycle.
4. Maintain `context[:conversation_history]` behavior from ADR 0019.
5. Preserve worker execution path for dependency-backed programs.

## Target Runtime Design

### Execution Receiver Model

1. Introduce `ExecutionSandbox` object instantiated per attempt.
2. Sandbox holds attempt-local runtime state:
   - `context`
   - `args`
   - `kwargs`
   - `result`
3. Generated code executes in sandbox method binding.
4. Sandbox is discarded after call completion.

### Forwarded API Surface (v1)

Sandbox forwards to parent Agent:

1. `tool(...)`
2. `delegate(...)`
3. `remember(...)`
4. `memory`

Generated code continues to reference `Agent::Outcome` directly via constant.

### Lifecycle Guarantees

1. Method definitions created by generated code are sandbox-local only.
2. Agent method lookup remains unchanged across attempts.
3. Contract validation, guardrail policy, and outcome repair lanes remain runtime-owned.

## Phased Delivery Plan

### Phase 0: Baseline and Regression Fixtures

Goals:

1. Capture pre-change behavior for comparison.
2. Add tests that fail on current leakage behavior.

Tasks:

1. Capture log traces for Google/Yahoo/NYT sequence with current receiver behavior.
2. Add regression spec:
   - execute generated code containing `def leaked_helper`; assert helper is not available on Agent after call (expected to fail pre-fix).
3. Add trace assertion fixture strategy for delegated call visibility.

Exit criteria:

1. Baseline traces archived.
2. Leakage regression test exists and fails pre-fix.

### Phase 1: Introduce ExecutionSandbox Primitive

Goals:

1. Move local eval path from Agent binding to sandbox binding.

Tasks:

1. Add [`runtimes/ruby/lib/recurgent/execution_sandbox.rb`](../../runtimes/ruby/lib/recurgent/execution_sandbox.rb).
2. Refactor `_execute_code` to construct sandbox and execute wrapped code there.
3. Keep `result` contract unchanged (raw domain value returned to caller pipeline).
4. Keep pre/post tool-registry integrity checks around sandbox execution.

Primary files:

1. [`runtimes/ruby/lib/recurgent/execution_sandbox.rb`](../../runtimes/ruby/lib/recurgent/execution_sandbox.rb)
2. [`runtimes/ruby/lib/recurgent.rb`](../../runtimes/ruby/lib/recurgent.rb)

Exit criteria:

1. Existing dynamic-call tests pass with sandbox receiver.
2. No new failures in worker-backed path tests.

### Phase 2: Forwarded Surface Hardening

Goals:

1. Ensure sandbox exposes only intended runtime API.

Tasks:

1. Implement explicit forwarding methods only (`tool`, `delegate`, `remember`, `memory`).
2. Ensure `context/args/kwargs/result` locals are available to generated code as before.
3. Add behavior tests for each forwarded method.
4. Verify generated code that references `self` cannot access unintended Agent internals.

Primary files:

1. [`runtimes/ruby/lib/recurgent/execution_sandbox.rb`](../../runtimes/ruby/lib/recurgent/execution_sandbox.rb)
2. [`runtimes/ruby/spec/recurgent_spec.rb`](../../runtimes/ruby/spec/recurgent_spec.rb)

Exit criteria:

1. Forwarded API tests pass.
2. No accidental host mutation through sandbox path.

### Phase 3: Observability and Rollout Signal

Goals:

1. Make execution receiver explicit in logs.
2. Enable trace-level before/after calibration.

Tasks:

1. Add `execution_receiver` field in logs (`legacy` | `sandbox` during rollout; `sandbox` after migration).
2. Thread receiver field through call state/log entry builders.
3. Update observability documentation for the new field.

Primary files:

1. [`runtimes/ruby/lib/recurgent/call_state.rb`](../../runtimes/ruby/lib/recurgent/call_state.rb)
2. [`runtimes/ruby/lib/recurgent/observability.rb`](../../runtimes/ruby/lib/recurgent/observability.rb)
3. [`runtimes/ruby/lib/recurgent/observability_attempt_fields.rb`](../../runtimes/ruby/lib/recurgent/observability_attempt_fields.rb)
4. [`docs/observability.md`](../observability.md)

Exit criteria:

1. New logs include `execution_receiver`.
2. Delegated trace analysis can filter by receiver reliably.

### Phase 4: Lifecycle Integrity Regression Suite

Goals:

1. Prove fix closes the leakage class without regressing lifecycle behaviors.

Tasks:

1. Add regression test: generated `def fetch_headlines` in one call does not alter next call dispatch behavior.
2. Add test: repeated assistant-style calls preserve delegated depth-1 traces when tools are reused.
3. Add test: ADR 0016 retry lanes still function under sandbox (`guardrail`, `execution`, `outcome` repair).
4. Add test: conversation history append still occurs once per logical call (no duplication under retries).

Primary files:

1. [`runtimes/ruby/spec/recurgent_spec.rb`](../../runtimes/ruby/spec/recurgent_spec.rb)
2. [`runtimes/ruby/spec/acceptance/recurgent_acceptance_spec.rb`](../../runtimes/ruby/spec/acceptance/recurgent_acceptance_spec.rb)

Exit criteria:

1. Leakage regression passes.
2. Retry/rollback and history invariants remain green.

### Phase 5: End-to-End Validation and Cleanup

Goals:

1. Validate real behavior on favorite scenarios.
2. Complete migration to sandbox-only receiver.

Tasks:

1. Run Google/Yahoo/NYT scenario and inspect logs:
   - delegated calls remain visible at depth 1 when tools are used,
   - no missing traces due to method leakage,
   - receiver field confirms sandbox path.
2. Run movie scenario where tool creation previously triggered guardrail issues; verify no new receiver regressions.
3. Remove legacy receiver fallback path (if temporarily present).

Exit criteria:

1. Sandbox is the only execution receiver.
2. Real traces confirm delegation fidelity improvement.

## Testing Strategy

### Unit Tests

1. Sandbox returns `result` correctly with assignment and with `return`.
2. Sandbox forwards `tool`, `delegate`, `remember`, `memory`.
3. Generated method definition in sandbox does not appear on Agent instance/class after call.

### Integration Tests

1. Dynamic call flow still produces typed `Outcome`.
2. Guardrail violation and execution retry lanes still retry under sandbox.
3. Outcome repair lane still retries retriable errors and logs attempt counters.

### Acceptance Tests

1. Google/Yahoo/NYT favorite sequence:
   - verify output quality does not regress materially,
   - verify delegated depth-1 traces where tool calls are made.
2. Movie follow-up scenario:
   - verify no execution-surface regressions,
   - verify user-correction signals still emit.

## Observability Additions

Add field:

1. `execution_receiver`:
   - `legacy` (only during transitional rollout, if used),
   - `sandbox` (target steady state).

Recommended analysis checks:

1. Compare delegated depth-1 trace presence before/after sandbox adoption.
2. Confirm reduction in “apparent delegation without delegated trace” anomalies.

## Risks and Mitigations

1. Risk: generated code depended on broad Agent `self` surface.
   - Mitigation: strict forwarding + runtime repair feedback; add missing forwarders only with evidence.
2. Risk: refactor accidentally changes `result` semantics.
   - Mitigation: direct unit tests for result channel and control-flow semantics.
3. Risk: lifecycle drift in retries/history append.
   - Mitigation: explicit regression tests for ADR 0016 and ADR 0019 invariants.

## Completion Checklist

1. [ ] `ExecutionSandbox` implemented and wired into local eval path.
2. [ ] Forwarded API surface implemented and test-covered.
3. [ ] `execution_receiver` log field emitted and documented.
4. [ ] Leakage regression suite green.
5. [ ] Favorite scenario traces captured and analyzed post-migration.
6. [ ] Legacy receiver path removed (sandbox-only steady state).
7. [ ] Docs index and retrieval index updated.
