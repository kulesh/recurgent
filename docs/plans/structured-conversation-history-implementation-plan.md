# Structured Conversation History Implementation Plan

## Objective

Implement ADR 0019 by introducing a first-class, structured `context[:conversation_history]` in the Ruby runtime, expose it clearly in prompt policy, and gather evidence about how Tool Builders naturally use history before introducing recursion primitives.

Target outcomes:

1. Every dynamic call appends a consistent, structured history record.
2. Generated code can read `context[:conversation_history]` directly with no new runtime helper APIs.
3. Observability captures history-usage signals to guide future decisions on ADR 0018 (`ContextView`/`recurse`).
4. Existing delegation, contract validation, guardrails, and artifact policies remain unchanged.

## Design Alignment

This plan aligns with project tenets:

1. Agent-first mental model:
   - expose history as directly manipulable runtime data.
2. Tolerant interfaces by default:
   - stable required keys, additive optional fields, tolerant evolution.
3. Runtime ergonomics before constraints:
   - plain data first, no new control primitive yet.
4. Ubiquitous language:
   - Tool Builder uses history to shape behavior; runtime observes patterns.

## Scope

In scope:

1. Canonical `conversation_history` record schema and population lifecycle.
2. Prompt updates that make history availability explicit and actionable.
3. History-usage telemetry for evidence collection.
4. Unit/integration/acceptance tests and docs updates.

Out of scope:

1. `ContextView` class.
2. `recurse(...)` primitive.
3. Model tiering by depth.
4. Recursim integration work.
5. Autonomous runtime refactoring/splitting based on history usage.

## Current State Snapshot

Current behavior:

1. `context` is available to generated code and already used for ad hoc memory.
2. Prompt includes `<memory>#{@context.inspect}</memory>` but no canonical history contract.
3. Some generated code already writes `context[:conversation_history]` manually.
4. Observability logs include call identity and outcomes but not explicit history-usage signals.

Gaps:

1. No canonical history record schema.
2. No guaranteed lifecycle insertion point for history records.
3. No explicit prompt guidance about history structure and usage intent.
4. No metrics to evaluate if recursive primitives are actually needed.

## Canonical v1 History Record

Required fields (v1):

1. `call_id` (String)
2. `timestamp` (ISO8601 UTC String)
3. `speaker` (`"user" | "agent" | "tool"`)
4. `method_name` (String)
5. `args` (JSON-safe Array)
6. `kwargs` (JSON-safe Hash)
7. `outcome_summary` (Hash)

Optional additive fields (v1):

1. `trace_id`
2. `parent_call_id`
3. `depth`
4. `duration_ms`
5. `error_type`
6. `error_message`
7. `program_source`
8. `artifact_hit`

Schema policy:

1. required keys remain stable,
2. optional keys may be added over time,
3. values must remain JSON-safe.

## Runtime Design

### Insertion point

Append history in one deterministic place: dynamic call finalize path (`ensure`) after outcome is known.

Why:

1. outcome summary is complete,
2. call identity is available,
3. success/error paths are unified.

### Storage model

1. `context[:conversation_history]` must always normalize to an Array.
2. If absent, initialize to `[]`.
3. If malformed/non-array, coerce to `[]` and log a debug warning when `@debug` is true.

### Outcome summary shape

`outcome_summary` should include:

1. `status`
2. `ok`
3. `error_type`
4. `retriable`
5. `value_class` (if ok)

Do not store full `outcome_value` by default in history records to avoid runaway memory and sensitive duplication.

### Serialization constraints

1. Reuse runtime JSON-safety helpers for args/kwargs/outcome summary.
2. If serialization fails, replace problematic value with `inspect` fallback at field level.

## Prompting Changes

### System prompt

Add explicit guidance:

1. `context[:conversation_history]` is available as structured array records.
2. Prefer direct Ruby filtering/querying over speculative abstraction.
3. Do not assume all optional fields exist; code defensively.

### User prompt

Add lightweight structured metadata block:

1. history record count,
2. latest 1-3 record summaries (not full payload),
3. reminder that full history is accessible at runtime through `context[:conversation_history]`.

This keeps token usage bounded while preserving discoverability.

## Observability and Evidence Collection

Add explicit fields in log context/entry:

1. `history_record_appended` (boolean)
2. `conversation_history_size` (integer)
3. `history_access_detected` (boolean; static code signal)
4. `history_query_patterns` (array of tags such as `filter`, `map`, `slice`, `count`, `group`)

Detection strategy (v1):

1. Static code scan of generated `code` for `conversation_history` usage.
2. Pattern tagging by regex for common Ruby enumerable/query operators.
3. No runtime instrumentation hooks inside eval for v1.

## File-Level Plan

### Runtime core

1. [`runtimes/ruby/lib/recurgent/call_execution.rb`](../../runtimes/ruby/lib/recurgent/call_execution.rb)
   - append canonical conversation history record in call finalization path.
2. [`runtimes/ruby/lib/recurgent/call_state.rb`](../../runtimes/ruby/lib/recurgent/call_state.rb)
   - add state fields needed for history append and history-usage observability.
3. [`runtimes/ruby/lib/recurgent.rb`](../../runtimes/ruby/lib/recurgent.rb)
   - add private helpers for:
     - history storage normalization,
     - record construction,
     - outcome summary extraction,
     - JSON-safe field coercion.

### Prompting

1. [`runtimes/ruby/lib/recurgent/prompting.rb`](../../runtimes/ruby/lib/recurgent/prompting.rb)
   - system/user prompt updates for structured history guidance,
   - history preview block generation.

### Observability

1. [`runtimes/ruby/lib/recurgent/observability.rb`](../../runtimes/ruby/lib/recurgent/observability.rb)
   - include new history fields.
2. [`runtimes/ruby/lib/recurgent/capability_pattern_extractor.rb`](../../runtimes/ruby/lib/recurgent/capability_pattern_extractor.rb) (or dedicated helper)
   - add lightweight history-access pattern extraction.

### Tests

1. [`runtimes/ruby/spec/recurgent_spec.rb`](../../runtimes/ruby/spec/recurgent_spec.rb)
   - new unit/integration tests for history schema, append behavior, malformed context coercion, prompt inclusion, and log fields.
2. [`runtimes/ruby/spec/acceptance/recurgent_acceptance_spec.rb`](../../runtimes/ruby/spec/acceptance/recurgent_acceptance_spec.rb)
   - scenario proving generated code can read/use structured history reliably.

### Documentation

1. [`docs/product-specs/delegation-contracts.md`](../product-specs/delegation-contracts.md)
   - clarify interaction with conversation history (adjacent, not contract payload).
2. [`docs/observability.md`](../observability.md)
   - document new history telemetry fields and interpretation.
3. [`docs/index.md`](../index.md)
   - add this implementation plan entry.

## Delivery Phases

### Phase 0: Baseline and Safety

Goals:

1. Capture current behavior and log shape before runtime change.
2. Ensure no regressions in existing call lifecycle.

Tasks:

1. Capture sample traces from assistant and calculator examples.
2. Add failing/placeholder tests for canonical history behavior.

Exit criteria:

1. Baseline traces archived.
2. Test expectations written before implementation.

### Phase 1: Canonical History Schema + Append

Goals:

1. History records are always appended with canonical required fields.

Tasks:

1. Implement append in call finalization path.
2. Implement normalization/coercion for malformed `context[:conversation_history]`.
3. Ensure all inserted fields are JSON-safe.

Exit criteria:

1. Each dynamic call appends exactly one record.
2. Required schema fields always present.

### Phase 2: Prompt Surface

Goals:

1. Tool Builders are explicitly told how to use history.

Tasks:

1. Add system prompt rule for structured history availability.
2. Add user prompt history preview metadata block.
3. Keep token footprint bounded via small preview window.

Exit criteria:

1. Prompts include explicit history guidance.
2. Preview is present and bounded.

### Phase 3: Observability Signals

Goals:

1. Capture evidence of how agents use conversation history.

Tasks:

1. Add history append/size fields to logs.
2. Add static history-access detection and query-pattern tags.
3. Include fields in debug and non-debug pathways where appropriate.

Exit criteria:

1. Logs show usage signals for every call.
2. Pattern tags are stable and test-covered.

### Phase 4: Hardening and Edge Cases

Goals:

1. Make behavior robust for unusual payloads and failures.

Tasks:

1. Validate behavior with nil/empty args, large kwargs, error outcomes.
2. Validate no history append duplication across guardrail retries.
3. Validate history appends on both success and error paths.

Exit criteria:

1. No duplicate records per final call outcome.
2. Guardrail retry and persisted paths remain correct.

### Phase 5: Rollout and Calibration

Goals:

1. Ship safely and gather evidence for ADR 0018 decision point.

Tasks:

1. Run acceptance scenarios and inspect logs.
2. Validate no regression in lint/spec suites.
3. Document evidence-review checklist for deciding if recursion primitives are warranted.

Exit criteria:

1. Stable production behavior.
2. Sufficient evidence stream available for next architecture decision.

## Testing Strategy

Unit tests:

1. Initializes missing history array.
2. Coerces malformed history to empty array.
3. Appends canonical required fields.
4. Produces JSON-safe args/kwargs/outcome summary.
5. Preserves additive optional fields without schema break.

Integration tests:

1. End-to-end dynamic call appends one history record.
2. Error outcomes still append record with error summary.
3. Prompt contains history guidance and bounded preview.
4. Log entry contains history telemetry fields.

Acceptance tests:

1. Tool Builder reads prior conversation turns from structured history.
2. Re-ask style scenario uses history context in generated response logic.
3. Existing delegation/contract flows continue to pass unchanged.

Regression focus areas:

1. Guardrail retry lifecycle interaction with history appends.
2. Artifact replay path vs fresh generation path consistency.
3. UTF-8 and JSON serialization boundaries.

## Risks and Mitigations

1. Risk: history grows without bound and bloats prompt memory.
Mitigation: bounded prompt preview; full data remains runtime-accessible.
2. Risk: sensitive or bulky values leak into history.
Mitigation: outcome summary is compact by design; avoid full value storage by default.
3. Risk: non-serializable args/kwargs corrupt records.
Mitigation: field-level JSON-safe coercion with inspect fallback.
4. Risk: noisy history-access detection false positives.
Mitigation: treat as advisory telemetry, not correctness gate.

## Operational Checklist

Before merge:

1. `mise exec -- bundle exec rspec`
2. `mise exec -- bundle exec rubocop`
3. Manually run assistant example and inspect log for new history fields.

After merge:

1. Track history usage telemetry for at least one iteration window.
2. Summarize observed decomposition patterns.
3. Reassess ADR 0018 with evidence.

## Success Metrics

1. `conversation_history` append success rate: 100% of dynamic calls.
2. Prompt history guidance presence: 100% of generated calls.
3. History-access detection present in logs for calls whose code references history.
4. No regression in existing test suite and acceptance traces.
5. Clear evidence report generated for next architecture review.
