# Guardrail Exhaustion Boundary Normalization Implementation Plan

## Objective

Implement ADR 0022 with a generic lifecycle policy:

1. Exhausted guardrail retries never leak raw internal diagnostics to end users.
2. Internal diagnostics remain fully preserved for repair, observability, and evolution.
3. Policy applies uniformly across guardrail subtypes, with no domain-specific runtime branches.

## Design Constraints

1. Subtype-agnostic user-facing messaging in v1.
2. Normalization scope is top-level boundary only (`depth == 0`) in v1.
3. No change to retry semantics from ADR 0016.
4. No semantic coercion of successful outcomes (ADR 0017).
5. Preserve tolerant interfaces and existing typed outcome vocabulary where possible.

## Scope

In scope:

1. Structured subtype metadata for guardrail violations.
2. Top-level normalization for exhausted recoverable guardrails.
3. Observability fields for normalized vs raw lifecycle views.
4. Tests proving no internal string leakage at user boundary.

Out of scope:

1. Domain-specific policy lanes (movies/news/etc.).
2. Reworking individual guardrail invariants.
3. Depth-1+ normalization.

## Implementation Strategy

Deliver in five phases. Each phase is independently verifiable.

### Phase 0: Taxonomy and Data Contract

Goals:

1. Standardize guardrail subtype metadata shape.
2. Define normalization payload contract.

Implementation:

1. Add/confirm a canonical `violation_subtype` key in guardrail classification metadata.
2. Define normalization metadata shape on surfaced outcome:
   - `normalized: true`
   - `normalization_policy: "guardrail_exhaustion_boundary_v1"`
   - `guardrail_class`
   - `guardrail_subtype`
   - `guardrail_recovery_attempts`
3. Keep raw violation message under internal/debug metadata fields only.

Suggested files:

1. `runtimes/ruby/lib/recurgent/guardrail_policy.rb`
2. `runtimes/ruby/lib/recurgent/guardrail_code_checks.rb`

Exit criteria:

1. Every guardrail violation can be traced to a subtype.
2. Metadata schema is documented in tests.

### Phase 1: Top-Level Boundary Normalization

Goals:

1. Normalize exhausted recoverable guardrails at user boundary.
2. Prevent raw internal diagnostics from surfacing in user-facing error strings.

Implementation:

1. Add a top-level-only normalization step when producing error outcomes for exhausted guardrail retries.
2. Apply normalization only when call depth is zero.
3. Use v1 subtype-agnostic user message:
   - `"This request couldn't be completed after multiple attempts."`
4. Preserve internal diagnostics in metadata/log entries.

Suggested files:

1. `runtimes/ruby/lib/recurgent.rb`
2. `runtimes/ruby/lib/recurgent/call_execution.rb`

Exit criteria:

1. Top-level exhausted guardrail responses are normalized.
2. Depth-1+ tool errors are unnormalized.

### Phase 2: Observability and Trace Fidelity

Goals:

1. Make normalization behavior measurable.
2. Keep dual-view visibility: user-facing normalized and internal raw.

Implementation:

1. Add observability fields:
   - `guardrail_violation_subtype`
   - `user_outcome_normalized`
   - `user_outcome_normalization_policy`
2. Ensure raw guardrail message remains in debug/internal fields only.
3. Add subtype counts for maintenance aggregation.

Suggested files:

1. `runtimes/ruby/lib/recurgent/observability.rb`
2. `runtimes/ruby/lib/recurgent/observability_attempt_fields.rb`
3. `runtimes/ruby/lib/recurgent/artifact_metrics.rb`

Exit criteria:

1. Logs can answer:
   - what subtype fired,
   - whether user normalization occurred,
   - what policy version normalized it.

### Phase 3: Test Matrix

Goals:

1. Lock in boundary semantics with deterministic tests.
2. Prove no regression in repair/orchestration behavior.

Unit tests:

1. Guardrail subtype tagging exists for multiple subtypes:
   - `missing_external_provenance`
   - `context_tools_shape_misuse`
   - `singleton_method_mutation`
2. Top-level exhaustion normalizes message and type.
3. Normalized message does not contain raw guardrail internals.
4. Depth-1 exhaustion remains raw for parent orchestration.

Integration tests:

1. End-user receives generic normalized message for exhausted guardrail.
2. Same trace contains raw subtype/message in logs.
3. Parent tool can still branch on raw subtype from child outcome.

Suggested files:

1. `runtimes/ruby/spec/recurgent_spec.rb`
2. `runtimes/ruby/spec/acceptance/recurgent_acceptance_spec.rb`

Exit criteria:

1. Tests cover both normalized boundary and raw internal behavior paths.

### Phase 4: Live Trace Validation

Goals:

1. Validate in real assistant runs, not only stubs.
2. Confirm generic behavior across at least two guardrail subtypes.

Validation scenarios:

1. Provenance subtype path (`missing_external_provenance`) with exhausted retries.
2. Non-provenance subtype path (for example `context[:tools]` shape misuse).

For each scenario verify:

1. User-facing response uses subtype-agnostic normalized message.
2. JSONL entry includes subtype and raw diagnostics.
3. No domain-specific branching appears in runtime code path.

Artifacts:

1. Save console traces under `tmp/` or baseline fixture directory.
2. Record call IDs and relevant JSONL snippets in a short validation note.

Exit criteria:

1. No user-visible raw guardrail internals in validated traces.
2. Internal subtype diagnostics remain accessible for debugging and evolution.

## Rollout and Safety

1. Start with tests + log assertions before changing user-facing strings.
2. Apply normalization in one central boundary function only.
3. Keep mapping table minimal in v1:
   - one generic message for all exhausted recoverable guardrails.
4. Add subtype-aware templates only after explicit evidence and ADR update.

## Completion Checklist

1. ADR 0022 remains `proposed` or is moved to `accepted` after implementation review.
2. Runtime emits guardrail subtype metadata consistently.
3. Top-level boundary normalization is active with v1 generic message.
4. Depth-1+ paths preserve raw typed errors.
5. Observability captures normalized + raw lifecycle views.
6. `mise exec -- bundle exec rspec` passes.
7. `mise exec -- bundle exec rubocop` passes.
