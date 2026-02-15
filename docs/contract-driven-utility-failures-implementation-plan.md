# Contract-Driven Utility Failures Implementation Plan

## Objective

Implement ADR 0017 so utility quality pressure is agent-visible and contract-driven, while runtime remains observational for semantics.

Target outcome:

1. Runtime does not rewrite Tool-authored success into failure.
2. Inline utility failures are enforced through machine-checkable contract constraints.
3. Weak-success drift is captured as telemetry and pushed into out-of-band evolution loops.

## Design Alignment

This plan explicitly follows project tenets:

1. Agent-first mental model:
   - Tool Builders own contract quality.
   - Tools own truthful success/failure semantics.
2. Tolerant interfaces by default:
   - Keep symbol/string key equivalence and tolerant shape canonicalization.
   - Add explicit constraints only where utility quality must fail fast.
3. Runtime ergonomics and clarity:
   - Runtime enforces deterministic contract checks.
   - Runtime does not silently reinterpret Tool intent.
4. Ubiquitous language:
   - Tool Builder forges enforceable contracts.
   - Tool succeeds meaningfully or fails honestly.
   - Worker executes.

## Scope

In scope:

1. Remove runtime semantic coercion (`ok` -> `low_utility` by status string).
2. Add enforceable utility constraints under `deliverable` validation.
3. Preserve and strengthen Tool-authored `low_utility` / `wrong_tool_boundary` path.
4. Add weak-success telemetry as observational signals.
5. Feed signals into out-of-band maintenance/evolution recommendations.
6. Update docs and tests to reflect new contract-first quality model.

Out of scope:

1. Runtime-autonomous tool splitting/decomposition.
2. Domain-specific hardcoded scraping policies.
3. Lua parity work.

## Current State

Implemented already:

1. ADR 0014 delegated outcome boundary validation (shape/required keys + tolerant key semantics).
2. ADR 0015 typed outcomes (`low_utility`, `wrong_tool_boundary`) as vocabulary.
3. ADR 0016 validation-first fresh-call lifecycle and retry mechanisms.
4. Prompt nudges for Tool self-evaluation and Outcome API usage.

Gap to close:

1. Runtime currently includes a semantic coercion path for weak success strings.
2. `acceptance` prose is not machine-checkable at runtime.
3. Weak-success telemetry is not yet first-class in out-of-band evolution scoring.

## Phased Plan

### Phase 0: Baseline and Safety Rails

Goals:

1. Lock current behavior with baseline traces.
2. Define migration guardrails before runtime behavior shift.

Implementation:

1. Capture baseline traces for:
   - movie scenario (weak success/no parse),
   - Google/Yahoo/NYT sequence,
   - one deterministic non-open-world scenario (control).
2. Add feature marker in code comments for ADR 0017 path boundaries.
3. Ensure debug logs expose enough fields to compare pre/post behavior.

Exit criteria:

1. Baseline artifacts and traces documented.
2. No ambiguity about expected post-change differences.

### Phase 1: Remove Semantic Coercion

Goals:

1. Runtime no longer rewrites Tool-authored success intent.

Implementation:

1. Remove weak-status `Outcome.ok` -> `Outcome.error(low_utility)` conversion from boundary validator.
2. Keep shape validation and tolerant canonicalization untouched.
3. Update/replace tests that depended on coercion behavior.

Key files:

1. `runtimes/ruby/lib/recurgent/outcome_contract_validator.rb`
2. `runtimes/ruby/spec/recurgent_spec.rb`

Exit criteria:

1. No code path performs semantic success->error rewriting.
2. Test suite passes with updated expectations.

### Phase 2: Enforceable Utility Constraints in Deliverable

Goals:

1. Move inline utility failure pressure into deterministic contract checks.

Implementation (v1 constraint set):

1. Add minimal machine-checkable deliverable constraints:
   - array: `min_items`
   - object: per-field constraints for required keys where value is an array (`min_items`)
2. Keep constraints optional and backward-compatible.
3. On violation, return typed `contract_violation` with metadata:
   - `mismatch`,
   - expected vs actual shape/value summary,
   - failing key/path.

Suggested schema shape (v1):

```yaml
deliverable:
  type: object
  required: [status, movies]
  constraints:
    properties:
      movies:
        type: array
        min_items: 1
```

Key files:

1. `runtimes/ruby/lib/recurgent/outcome_contract_shapes.rb`
2. `runtimes/ruby/lib/recurgent/outcome_contract_validator.rb`
3. `runtimes/ruby/spec/recurgent_spec.rb`

Exit criteria:

1. Empty result arrays fail only when contract says so.
2. Violations are deterministic, typed, and repair-visible.

### Phase 3: Prompt + Contract Authoring Updates

Goals:

1. Teach Tool Builders to express utility requirements in enforceable contracts.
2. Keep `acceptance` as explanatory intent, not runtime-enforced logic.

Implementation:

1. Update prompt guidance:
   - “If utility must fail inline, encode as deliverable constraints.”
2. Add contract examples in prompts/docs showing `min_items` usage.
3. Keep nudge for Tool-authored `low_utility` / `wrong_tool_boundary` on open-world uncertainty.

Key files:

1. `runtimes/ruby/lib/recurgent/prompting.rb`
2. `docs/delegation-contracts.md`
3. `docs/tolerant-delegation-interfaces.md` (if needed for examples)

Exit criteria:

1. Prompt examples align with runtime-enforceable contract model.
2. Docs clearly separate enforceable constraints vs prose acceptance.

### Phase 4: Weak-Success Telemetry (Observational Only)

Goals:

1. Detect weak-success patterns without mutating outcome semantics.

Implementation:

1. Add observational weak-success flags in call telemetry when heuristics match (for example `success_no_parse`, empty arrays under “success” statuses).
2. Record as separate telemetry fields; do not alter status/outcome.
3. Link weak-success events with `user_correction` when available.

Key files:

1. `runtimes/ruby/lib/recurgent/observability.rb`
2. `runtimes/ruby/lib/recurgent/pattern_memory_store.rb`
3. `runtimes/ruby/lib/recurgent/user_correction_signals.rb`

Exit criteria:

1. Weak-success is queryable in logs and pattern memory.
2. Outcome semantics remain Tool-authored.

### Phase 5: Out-of-Band Evolution Pressure Integration

Goals:

1. Convert repeated weak-success + correction evidence into Tool Builder pressure.

Implementation:

1. Extend maintenance/evaluator flow to score:
   - weak-success frequency,
   - correction-linked weak-success,
   - boundary referral counts.
2. Emit recommendations:
   - strengthen contract constraints,
   - re-forge implementation,
   - split boundary when repeated `wrong_tool_boundary`.
3. Keep recommendations advisory (no autonomous runtime mutation).

Key files:

1. `runtimes/ruby/lib/recurgent/tool_maintenance.rb`
2. `bin/recurgent-tools` (if CLI output surface is expanded)
3. `docs/observability.md`

Exit criteria:

1. Repeated weak-success contributes to evolution recommendations.
2. Recommendation output is inspectable and deterministic.

### Phase 6: Validation, Rollout, and Calibration

Goals:

1. Validate behavior end-to-end in real scenarios.
2. Tune constraint strictness and telemetry signals.

Implementation:

1. Run acceptance traces:
   - Google/Yahoo/NYT,
   - movie scenario with follow-up ask,
   - non-open-world control tasks.
2. Compare before/after:
   - fewer silent compensations,
   - clearer typed failures from contracts,
   - stronger evolution signals out-of-band.
3. Tune thresholds where needed (weak-success heuristics and recommendation scoring).

Exit criteria:

1. Reliability remains stable.
2. Emergent adaptation loop is clearer and more explicit.

## Testing Strategy

Unit tests:

1. Deliverable constraint validator (`min_items`, missing path, wrong type).
2. Boundary validator does not coerce semantic success.
3. Telemetry flags weak-success without status mutation.

Integration tests:

1. Contract violation for empty movie list when `min_items: 1`.
2. Persisted repair path triggers on contract-driven failure.
3. Repeated weak-success + re-ask produces evolution signal.

Regression tests:

1. Existing tolerant key equivalence remains intact.
2. Existing guardrail retry and fresh execution repair flow remains intact.

Manual acceptance:

1. `examples/assistant.rb` movie scenario.
2. Google/Yahoo/NYT scenario with trace analysis.

## Migration Notes

1. Existing contracts without constraints remain valid and unchanged.
2. No artifact key changes required.
3. Behavior changes only when:
   - explicit constraints are present, or
   - telemetry/evaluator consumers use new weak-success fields.

## Risks and Mitigations

1. Risk: over-strict constraints produce false failures.
   - Mitigation: start with minimal constraint vocabulary and conservative defaults.
2. Risk: weak-success heuristics become noisy.
   - Mitigation: keep observational-only, calibrate against user-correction links.
3. Risk: prompt/docs drift from runtime enforcement.
   - Mitigation: add contract examples tied to validator tests.

## Deliverables Checklist

1. [ ] Runtime semantic coercion removed.
2. [ ] Deliverable utility constraints implemented (`min_items` v1).
3. [ ] Prompt guidance updated to contract-first utility enforcement.
4. [ ] Weak-success telemetry fields implemented.
5. [ ] Out-of-band evaluator consumes weak-success + correction signals.
6. [ ] Unit/integration/regression tests passing.
7. [ ] Documentation updated (ADR index, docs index, contracts guidance).
