# Outcome Boundary Contract Validation Implementation Plan

## Objective

Implement ADR 0014 so delegated Tool boundaries are validated by runtime, interfaces remain tolerant and idiomatic in Ruby, and interface drift is reduced through canonical method visibility.

This plan preserves:

1. Agent-first control of Tool design and promotion.
2. Tolerant interfaces by default (symbol/string key equivalence).
3. Runtime ergonomics and clarity before speculative generalization.

## Scope

In scope:

1. Runtime validation of delegated `Outcome.ok` values against delegation `deliverable` contracts.
2. Tolerant key-equivalence validation for object contracts.
3. Typed contract-violation errors with repair-oriented metadata.
4. Canonical Tool method metadata (`methods`) in registry and prompt injection.
5. Agent-driven alias consolidation signals (observation only, not runtime auto-mutation).
6. Contracted-tool precondition hardening for nil/empty required inputs.

Out of scope:

1. Full JSON Schema implementation for deliverables.
2. Runtime-autonomous method renaming/merging.
3. Lua runtime parity.

## Current State Snapshot

What works now:

1. Tool forging, reuse, cacheability gating, and pattern memory are operational.
2. Dynamic dispatcher methods are persisted for observability but not reused.
3. Known-tool prompt injection includes role/purpose metadata.

Observed integration gaps from Google/Yahoo/NYT traces:

1. Producer/consumer shape mismatch (`:body` vs `"body"`) crossed boundary silently.
2. Method drift appeared (`fetch_url` and `fetch`) on the same tool capability.
3. Parser accepted `nil` input and returned empty success instead of typed failure.
4. Delegation contracts were declared but not enforced at runtime success boundary.

## Design Constraints

1. Contract enforcement must be tolerant for Ruby hash key idioms.
2. Validator must be lightweight and deterministic.
3. Boundary failures must produce typed `Outcome.error`, never silent success.
4. Canonical method metadata should inform Agent choices without hard-locking interface evolution.
5. Runtime should provide observations/signals; Agent makes consolidation decisions.

## Delivery Strategy

Deliver in six phases. Each phase is independently testable.

### Phase 0: Contract Matrix and Baseline Traces

Goals:

1. Define v1 deliverable-validation matrix and failure taxonomy.
2. Capture baseline traces for regression comparisons.

Implementation:

1. Document v1 deliverable checks:
   - `type: object` + `required` keys.
   - `type: array` shape checks (array presence only in v1 unless item keys declared).
2. Define mismatch taxonomy:
   - `missing_required_key`
   - `type_mismatch`
   - `nil_required_input`
3. Capture and archive baseline traces under `docs/baselines/<date>/`:
   - Google News, Yahoo News, NYT sequence.
4. Add expected post-fix outcomes for the same sequence.

Exit criteria:

1. Validation matrix is documented and agreed.
2. Baseline fixtures committed for before/after comparison.

### Phase 1: Delegated Outcome Boundary Validator

Goals:

1. Validate delegated success outcomes against `deliverable`.
2. Convert violations to typed errors.

Implementation:

1. Add `OutcomeContractValidator` module.
2. Validation trigger:
   - when `@delegation_contract` exists,
   - and call result is `Outcome.ok`.
3. Validator input:
   - `deliverable`, `outcome.value`, `tool_role`, `method_name`.
4. On violation, return:
   - `Outcome.error(error_type: "contract_violation", retriable: false, ...)`
   - include violation metadata:
     - `expected_shape`
     - `actual_shape`
     - `expected_keys`
     - `actual_keys`
     - `mismatch`
5. Classify boundary violation as non-extrinsic failure class for repair/regeneration flow.

Suggested files:

1. [`runtimes/ruby/lib/recurgent/outcome_contract_validator.rb`](../../runtimes/ruby/lib/recurgent/outcome_contract_validator.rb)
2. [`runtimes/ruby/lib/recurgent/call_execution.rb`](../../runtimes/ruby/lib/recurgent/call_execution.rb)
3. [`runtimes/ruby/lib/recurgent/call_state.rb`](../../runtimes/ruby/lib/recurgent/call_state.rb)
4. [`runtimes/ruby/lib/recurgent/observability.rb`](../../runtimes/ruby/lib/recurgent/observability.rb)

Exit criteria:

1. Contract-shape mismatch cannot return `Outcome.ok`.
2. Violations are typed, observable, and include shape metadata.

### Phase 2: Tolerant Key Equivalence at Validation Boundary

Goals:

1. Make object-key checks tolerant for Ruby symbol/string keys.
2. Prevent false violations from key-type differences.

Implementation:

1. Implement key-equivalence helper used only by validator:
   - required key `"body"` satisfied by `value["body"]` or `value[:body]`.
2. Keep runtime payload unchanged (no global key normalization).
3. Ensure metadata reports both expected and actual keys for diagnostics.

Suggested files:

1. [`runtimes/ruby/lib/recurgent/outcome_contract_validator.rb`](../../runtimes/ruby/lib/recurgent/outcome_contract_validator.rb)
2. [`runtimes/ruby/spec/recurgent_spec.rb`](../../runtimes/ruby/spec/recurgent_spec.rb)

Exit criteria:

1. Symbol/string-only mismatch no longer fails validation.
2. True missing-key mismatches still fail deterministically.

### Phase 3: Canonical Method Metadata in Registry and Prompts

Goals:

1. Reduce interface drift by surfacing existing method names.
2. Keep method metadata minimal in v1.

Implementation:

1. Extend registry entries with:
   - `methods: ["fetch_url", ...]` (names only in v1)
   - `aliases: []` (optional, initially empty)
2. Update method metadata on successful tool calls:
   - add called method name if missing.
3. Render method metadata in `<known_tools>` prompt block.
4. Preserve backward compatibility for existing registry entries without `methods`.

Suggested files:

1. [`runtimes/ruby/lib/recurgent/tool_store.rb`](../../runtimes/ruby/lib/recurgent/tool_store.rb)
2. [`runtimes/ruby/lib/recurgent/prompting.rb`](../../runtimes/ruby/lib/recurgent/prompting.rb)
3. [`runtimes/ruby/lib/recurgent/known_tool_ranker.rb`](../../runtimes/ruby/lib/recurgent/known_tool_ranker.rb)
4. [`runtimes/ruby/spec/recurgent_spec.rb`](../../runtimes/ruby/spec/recurgent_spec.rb)

Exit criteria:

1. Known-tools prompt includes canonical methods when available.
2. Existing tools continue to load without migration failures.

### Phase 4: Alias Observation and Agent-Driven Consolidation

Goals:

1. Detect overlapping method interfaces on same Tool role.
2. Nudge Agent toward consolidation without runtime auto-renaming.

Implementation:

1. Add observation signal when registry shows overlapping methods (for example `fetch` + `fetch_url`).
2. Inject bounded interface-overlap hint into depth-0 prompt context.
3. Do not auto-delete/merge methods in runtime.

Suggested files:

1. [`runtimes/ruby/lib/recurgent/pattern_prompting.rb`](../../runtimes/ruby/lib/recurgent/pattern_prompting.rb) (or dedicated prompt helper)
2. [`runtimes/ruby/lib/recurgent/tool_store.rb`](../../runtimes/ruby/lib/recurgent/tool_store.rb)
3. [`runtimes/ruby/spec/recurgent_spec.rb`](../../runtimes/ruby/spec/recurgent_spec.rb)

Exit criteria:

1. Overlap appears as observability/prompt signal.
2. Consolidation remains Agent-authored behavior.

### Phase 5: Contracted Tool Precondition Hardening

Goals:

1. Eliminate silent success on invalid required inputs.
2. Improve repairability from precise typed failures.

Implementation:

1. Prompt/runtime guidance for contracted tools:
   - nil/empty required input must return typed error.
2. Validate parser-like flows:
   - `parse(nil)` and `parse("")` -> typed error (`invalid_input` or `contract_violation`).
3. Ensure parent calls propagate these typed errors meaningfully.

Suggested files:

1. [`runtimes/ruby/lib/recurgent/prompting.rb`](../../runtimes/ruby/lib/recurgent/prompting.rb)
2. [`runtimes/ruby/spec/recurgent_spec.rb`](../../runtimes/ruby/spec/recurgent_spec.rb)
3. [`runtimes/ruby/spec/acceptance/recurgent_acceptance_spec.rb`](../../runtimes/ruby/spec/acceptance/recurgent_acceptance_spec.rb)

Exit criteria:

1. No silent empty-success on nil required inputs.
2. End-to-end sequence returns accurate errors or valid headlines.

## Data Contract Updates

### Registry (`tools/registry.json`) v1 extension

```json
{
  "tools": {
    "web_fetcher": {
      "purpose": "fetch and extract content from URLs",
      "methods": ["fetch_url"],
      "aliases": []
    }
  }
}
```

Rules:

1. `methods` are method names only in v1.
2. `aliases` are observational metadata; runtime does not auto-resolve behavior changes from aliases.
3. Missing `methods` implies legacy entry; runtime treats as unknown-method metadata, not error.

### Contract Violation Error Metadata

```json
{
  "error_type": "contract_violation",
  "error_message": "Delegated outcome does not satisfy deliverable contract",
  "metadata": {
    "expected_shape": "object",
    "actual_shape": "object",
    "expected_keys": ["body"],
    "actual_keys": ["status", ":body"],
    "mismatch": "missing_required_key"
  }
}
```

## Runtime Algorithm (Delegated Calls)

For a delegated tool call:

1. Execute generated/persisted code and coerce to `Outcome`.
2. If no active `@delegation_contract`, return outcome unchanged.
3. If outcome is error, return unchanged.
4. If outcome is success, validate `outcome.value` against `deliverable` contract.
5. If valid, return unchanged.
6. If invalid, replace with typed `contract_violation` outcome with metadata.
7. Emit observability fields for validation result.

## Test Strategy

### Unit Tests

1. Outcome validator:
   - object required key satisfied by string key.
   - object required key satisfied by symbol key.
   - missing required key -> `contract_violation`.
   - type mismatch -> `contract_violation`.
2. Registry method metadata:
   - method capture on success.
   - merge/update behavior.
   - legacy registry compatibility.

### Integration Tests

1. Boundary mismatch conversion:
   - delegated tool returns wrong shape, parent receives typed error.
2. Tolerant key equivalence:
   - delegated `{:body => ...}` satisfies required `"body"`.
3. Method visibility:
   - `<known_tools>` includes method list and influences generation fixtures.

### Acceptance Tests

1. Favorite sequence:
   - Google News -> Yahoo News -> NYT.
   - verify no empty-success due to nil parser input.
2. Interface drift scenario:
   - tool has both `fetch` and `fetch_url`; prompt includes overlap signal.
3. Negative case:
   - unrelated asks should not emit spurious method-overlap hints.

## Observability Additions

Add fields to call logs:

1. `contract_validation_applied` (bool)
2. `contract_validation_passed` (bool)
3. `contract_validation_mismatch` (nullable string)
4. `contract_validation_expected_keys` (array)
5. `contract_validation_actual_keys` (array)

## Rollout and Operations

1. Implement validator first, then method metadata.
2. Run acceptance sequence and compare against Phase 0 baseline traces.
3. Add maintenance command extension (optional):
   - `bin/recurgent-tools interfaces --role <role>`
4. Keep pruning/alias consolidation Agent-driven; runtime only reports observations.

## Risks and Mitigations

1. Risk: over-strict validation breaks previously tolerated outputs.
   - Mitigation: v1 validator limited to explicit contract fields and tolerant key equivalence.
2. Risk: method metadata bloat in prompt.
   - Mitigation: include top-N tools and compact method lists.
3. Risk: false overlap signals.
   - Mitigation: only emit overlap when methods map to same role and repeated capability traces support it.

## Completion Checklist

1. [ ] Outcome contract validator implemented and tested.
2. [ ] Tolerant key-equivalence checks implemented and tested.
3. [ ] Contract-violation metadata added and logged.
4. [ ] Registry `methods` metadata persisted and prompt-injected.
5. [ ] Alias overlap observation signal implemented (Agent-driven consolidation only).
6. [ ] Contracted parser/tool precondition failures return typed errors.
7. [ ] Google/Yahoo/NYT acceptance trace passes and is documented.
8. [ ] ADR 0014 status reviewed for `accepted` transition after stable rollout.
