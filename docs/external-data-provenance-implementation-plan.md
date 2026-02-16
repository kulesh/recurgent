# External Data Provenance Implementation Plan

## Objective

Implement ADR 0021 so any external-data success is evidence-backed, source-attributable, and evolution-friendly without violating ADR 0017 (no semantic coercion).

This plan preserves project tenets:

1. Agent-first mental model.
2. Tolerant interfaces by default.
3. Runtime ergonomics and clarity over hidden compensation.
4. Ubiquitous language aligned to Tool Builder / Tool / Worker cognition.

## Scope

In scope:

1. Provenance envelope contract for external-data `Outcome.ok`.
2. Prompt and contract guidance for provenance authoring.
3. Recoverable guardrail enforcement for missing provenance in external-data success paths.
4. Compact provenance references in conversation history.
5. Observability and health scoring signals for provenance quality.
6. Acceptance tests and trace validation workflow.

Out of scope:

1. Browser-render/JS execution support.
2. Domain-specific parsers (movies/news/recipes) as architecture policy.
3. Runtime semantic coercion of emitted outcomes.

## Current State Snapshot

What already exists:

1. Validation-first fresh generation and guardrail retry lanes (ADR 0016).
2. Outcome boundary contract validation (ADR 0014).
3. Observational runtime utility semantics (ADR 0017).
4. Structured conversation history with canonical schema (ADR 0019).

Observed gaps:

1. External-data tools can return `Outcome.ok` with weak or missing source evidence.
2. Follow-up source questions can fail due to absent provenance in history summaries.
3. Artifact health can over-report reliability when fallback data is returned as success.

## Design Constraints

1. Provenance enforcement must be a validation/guardrail invariant, not runtime success->error rewriting.
2. Guardrail detection for external-data behavior must be conservative and inspectable in v1.
3. Provenance schema must remain generic across domains.
4. Conversation history must remain compact (ADR 0019 context-capacity constraints).
5. Rollout must tolerate legacy artifacts and converge through repair.

## Delivery Strategy

Deliver in six phases. Each phase is independently testable and shippable.

### Phase 0: Provenance Contract Profile (v1)

Goals:

1. Finalize the v1 provenance field profile.
2. Define strict vs staged-required fields.

Implementation:

1. Define required fields for external-data success:
   - `provenance.sources` (array, min 1)
   - `provenance.sources[].uri`
   - `provenance.sources[].fetched_at`
   - `provenance.sources[].retrieval_tool`
   - `provenance.sources[].retrieval_mode` (`live|cached|fixture`)
2. Mark `content_fingerprint` optional in v1.
3. Define tolerant key-equivalence semantics (string/symbol).
4. Document acceptance assertion style for freshness:
   - `retrieval_mode is live` for freshness-critical flows.

Suggested files:

1. `docs/adrs/0021-external-data-provenance-invariant.md`
2. `docs/specs/delegation-contracts.md`
3. `docs/tolerant-delegation-interfaces.md`

Exit criteria:

1. Provenance profile documented and unambiguous.
2. Required vs optional fields are explicit.

### Phase 1: Prompt and Contract Authoring Alignment

Goals:

1. Make provenance the default authoring behavior for external-data tools.
2. Reduce shape mistakes in generated code.

Implementation:

1. Update system prompt guidance:
   - external-data `Outcome.ok` must include provenance.
   - `context[:tools]` registry shape remains explicit.
2. Add/refresh user prompt examples:
   - successful external fetch returning `data + provenance`.
   - fallback path returning typed `low_utility` with reason.
3. Add self-check lines:
   - "Did I include provenance for external-data success?"
4. Keep examples domain-generic.

Suggested files:

1. `runtimes/ruby/lib/recurgent/prompting.rb`
2. `runtimes/ruby/spec/recurgent_spec.rb`

Exit criteria:

1. Prompt text contains provenance invariant and example patterns.
2. Prompt tests cover provenance guidance presence.

### Phase 2: Guardrail Enforcement (Recoverable)

Goals:

1. Block fabricated external-data success in hot path.
2. Route violations through existing regeneration lanes.

Implementation:

1. Add/extend generated-code policy checks for missing provenance in external-data success flows.
2. Keep detector conservative in v1:
   - explicit `tool("web_fetcher")` / delegate-fetch patterns,
   - explicit `net/http`, `Net::HTTP`, concrete `http(s)://` usage.
3. On violation:
   - raise recoverable guardrail (`tool_registry_violation` lane in current taxonomy),
   - inject targeted correction hint in retry feedback.
4. Ensure checks run for both fresh and persisted artifact execution paths.

Suggested files:

1. `runtimes/ruby/lib/recurgent/guardrail_policy.rb`
2. `runtimes/ruby/lib/recurgent/guardrail_code_checks.rb`
3. `runtimes/ruby/lib/recurgent/call_execution.rb`
4. `runtimes/ruby/lib/recurgent/persisted_execution.rb`
5. `runtimes/ruby/spec/recurgent_spec.rb`

Exit criteria:

1. External-data `ok` without provenance cannot pass execution.
2. Recovery on next regeneration is demonstrated in tests.

### Phase 3: Contract Validator Support for Provenance Constraints

Goals:

1. Let Tool Builders express provenance expectations as machine-checkable deliverables.
2. Keep enforcement deterministic.

Implementation:

1. Extend deliverable-constraint validation for nested provenance keys where needed.
2. Add reusable helpers for:
   - required nested keys (`provenance.sources`)
   - enum validation (`retrieval_mode` in allowed set)
   - min items on source list.
3. Preserve tolerant key semantics at boundary.
4. On mismatch, return typed `contract_violation` with precise metadata.

Suggested files:

1. `runtimes/ruby/lib/recurgent/outcome_contract_validator.rb`
2. `runtimes/ruby/lib/recurgent/outcome_contract_shapes.rb`
3. `runtimes/ruby/lib/recurgent/outcome_contract_constraints.rb`
4. `runtimes/ruby/spec/recurgent_spec.rb`

Exit criteria:

1. Provenance contract constraints are enforceable via existing validator path.
2. Contract violations include actionable mismatch metadata.

### Phase 4: Conversation History Provenance References (Compact)

Goals:

1. Make "what's the source?" answerable from history.
2. Keep history records lightweight.

Implementation:

1. Extend appended `outcome_summary` for external-data calls with compact provenance refs:
   - `source_count`
   - `primary_uri`
   - `retrieval_mode`
2. Do not embed full source arrays in history.
3. Keep full provenance in logs/artifacts only.
4. Add canonical history query hints in prompts where needed.

Suggested files:

1. `runtimes/ruby/lib/recurgent/conversation_history.rb`
2. `runtimes/ruby/lib/recurgent/conversation_history_normalization.rb`
3. `runtimes/ruby/lib/recurgent/prompting.rb`
4. `runtimes/ruby/spec/recurgent_spec.rb`

Exit criteria:

1. Source follow-up queries can recover compact source info from history.
2. History payload growth remains bounded.

### Phase 5: Observability and Health Integration

Goals:

1. Turn provenance completeness into measurable reliability signals.
2. Improve artifact evolution pressure.

Implementation:

1. Log provenance completeness flags and retrieval_mode distribution in JSONL entries.
2. Add artifact metrics for:
   - missing-provenance guardrail failures,
   - fixture-heavy success patterns,
   - cached-only behavior in freshness-critical tools.
3. Feed signals into maintenance recommendations (out-of-band lane).

Suggested files:

1. `runtimes/ruby/lib/recurgent/observability.rb`
2. `runtimes/ruby/lib/recurgent/artifact_metrics.rb`
3. `runtimes/ruby/lib/recurgent/tool_maintenance.rb`
4. `docs/observability.md`

Exit criteria:

1. Provenance quality is visible in logs and maintenance outputs.
2. Repeated weak provenance patterns influence evolution priority.

### Phase 6: Acceptance Scenarios and Rollout Controls

Goals:

1. Prove end-to-end behavior under real assistant traces.
2. Roll out safely without breaking forward progress.

Implementation:

1. Add acceptance scenarios:
   - external fetch success with provenance present,
   - hardcoded fallback `ok` blocked and repaired,
   - source follow-up answered from compact history refs.
2. Capture before/after traces for:
   - movies query + source follow-up,
   - at least one additional non-movie external-data domain.
3. Rollout:
   - start with guardrail enabled in debug-first workflows,
   - monitor false-positive rate,
   - promote to default once stable.

Suggested files:

1. `runtimes/ruby/spec/acceptance/recurgent_acceptance_spec.rb`
2. `docs/baselines/<date>/` fixtures
3. `docs/architecture.md` (flow update)

Exit criteria:

1. Acceptance suite verifies provenance invariant end-to-end.
2. Trace review confirms fabricated-success suppression and source explainability.

Acceptance matrix (required):

1. Existing-tool lane (repair path evidence):
   - Domain: news (Google/Yahoo/NYT sequence).
   - Expectation: at least one legacy call initially violates provenance invariant, guardrail triggers recoverable retry/repair, final outcome is provenance-compliant.
2. Fresh-forge lane (prevention path evidence):
   - Domain: newly forged external-data tool (prefer weather or recipes).
   - Expectation: first successful external-data outcome already includes provenance (no guardrail repair required).

Pass criteria by lane:

1. Repair path:
   - violation detected deterministically,
   - retry/repair converges within configured budget,
   - final success includes required provenance fields.
2. Prevention path:
   - external-data success includes required provenance on first pass,
   - no provenance guardrail violation occurs in that flow.

## Data Contract (v1)

External-data success payload target shape:

```json
{
  "data": "<domain payload>",
  "provenance": {
    "sources": [
      {
        "uri": "https://example.com/feed",
        "fetched_at": "2026-02-16T00:00:00Z",
        "retrieval_tool": "web_fetcher",
        "retrieval_mode": "live",
        "content_fingerprint": "sha256:..."
      }
    ],
    "extraction_tool": "rss_parser",
    "extracted_at": "2026-02-16T00:00:01Z"
  }
}
```

Rules:

1. `content_fingerprint` optional in v1.
2. `retrieval_mode` required for each source.
3. Symbol/string key variants are tolerated at boundary.

## Test Strategy

Unit tests:

1. Guardrail catches missing provenance in explicit fetch-like success paths.
2. Guardrail recovery can regenerate compliant code within budget.
3. Contract validator enforces provenance constraints and enum checks.
4. History appender stores compact provenance refs only.

Integration tests:

1. Assistant flow can answer "what's the source?" from history after external-data response.
2. Persisted artifacts with legacy non-provenance success paths are repaired before success.

Acceptance tests:

1. Movie/news/recipe-style query returns external-data result with provenance.
2. Guidance-only or hardcoded fallback paths become typed failures, not success.
3. Existing-tool lane demonstrates guardrail+repair provenance convergence.
4. Fresh-forge lane demonstrates provenance-first generation without repair.

## Rollout Risks and Mitigations

Risk 1: false positives from fetch-like detector.  
Mitigation: conservative detector scope in v1 + trace review before widening.

Risk 2: legacy persisted artifacts fail guardrails frequently.  
Mitigation: rely on existing repair lanes and staged rollout with observability.

Risk 3: provenance bloat in context/history.  
Mitigation: compact history refs; keep full provenance only in logs/artifacts.

## Completion Checklist

1. ADR 0021 accepted and indexed.
2. Prompt guidance includes provenance invariant and examples.
3. Guardrail enforcement active for fresh + persisted execution paths.
4. Provenance constraints validated at delegated outcome boundary.
5. Conversation history stores compact provenance refs.
6. Observability exposes provenance quality signals.
7. Acceptance traces demonstrate source explainability and fabricated-success suppression.
