# Contract-First Role Profiles and State Continuity Implementation Plan

- Status: draft
- Date: 2026-02-20
- Scope: ADR 0024 rollout (updated after ADR 0025)

## Objective

Implement ADR 0024 as the semantic-coherence layer for role-style agents, with coordination-first constraints and explicit authority-gated profile lifecycle operations.

Primary outcomes:

1. Role semantics are explicit, versioned, and opt-in via `RoleProfile`.
2. Continuity drift (state-key/signature/shape disagreement across sibling methods) is observable, explainable, and repairable.
3. Constraint enforcement defaults to environmental coordination over role-wide scope, not prescriptive pinning.
4. Profile lifecycle mutations are proposal-based and authority-gated through ADR 0025 lanes.
5. Promotion decisions for profile-enabled roles combine reliability evidence (ADR 0023) with profile compliance evidence (ADR 0024).
6. Methods-first profile schema is removed (clean break); runtime/docs/examples adopt scope-first contracts only.

## Status Quo Baseline

Baseline observations before ADR 0024 enforcement (from [`docs/reports/adr-0025-phase-validation-report.md`](../reports/adr-0025-phase-validation-report.md) and recent trace runs):

1. Reliability and awareness evidence can look healthy while role semantics drift (for example, calculator produced an incorrect algebra result in reruns).
2. Tool-level guardrail and retry mechanisms are active, but they do not guarantee sibling-method state continuity for role-style interfaces.
3. Non-profile flows remain operational under tolerant interfaces, with failures surfacing primarily as recoverable guardrail exhaustion rather than typed continuity diagnostics.

## Expected Improvements

1. Profile-enabled role calls expose explicit continuity pass/fail evidence for every constrained family.
2. Calculator continuity-drift class shifts from silent correctness drift to typed recoverable `role_profile_continuity_violation` with correction hints.
3. Durable eligibility for profile-enabled roles improves semantic precision by combining reliability and profile-compliance signals.
4. False promotion of semantically inconsistent role artifacts drops relative to pre-profile baseline.

## Non-Improvement Expectations

1. Non-profile tools remain on reliability-only lifecycle policy and do not require role profile adoption.
2. Tolerant interface behavior for existing non-profile capabilities remains unchanged.
3. ADR 0025 authority boundaries remain unchanged (`enact` denied by default without explicit approval).

## Validation Signals and Thresholds

1. Tests: full Ruby suite remains green at every phase gate.
2. Trace fields: `active_role_profile_version`, continuity violation records, correction hints, and profile compliance summaries are present where expected.
3. Rollout thresholds:
   - minimum observation window for promotion coupling: `>= 10` calls across `>= 2` sessions,
   - profile-enabled durable eligibility requires continuity pass-rate at or above configured threshold (initial target `>= 0.99`),
   - specialization of thresholds only when class false-hold or false-promotion exceeds `2x` global average.

## Rollback or Adjustment Triggers

1. Coordination enforcement causes repeated terminal failures beyond retry budget in stable scenarios -> revert affected role to shadow mode and tune correction hints before re-enabling enforcement.
2. Profile coupling creates material false holds for one capability class (`> 2x` global average) -> keep global defaults for others and introduce class-specific thresholds only for the outlier class.
3. Non-profile regressions after continuity rollout -> isolate and remove unintended coupling so non-profile paths remain reliability-only.

## Non-Goals

1. No automatic runtime inference of "this agent is a role".
2. No domain-specific semantic grader beyond authored profile constraints.
3. No bypass of ADR 0025 authority gates for profile creation, versioning, or mode changes.
4. No forced prescriptive canonical key/shape in coordination mode.
5. No backward-compatibility layer for legacy methods-first role-profile schema.

## Design Constraints

1. Separate reliability from correctness:
   - Reliability: execution stability and success signals (ADR 0023).
   - Correctness: role continuity/profile compliance (ADR 0024).
2. Coordination mode is default:
   - enforce agreement among siblings,
   - do not dictate specific key names/shapes.
3. Scope defaults to role-wide:
   - `scope: all_methods` unless explicitly narrowed,
   - new forged methods are included automatically,
   - explicit method lists are opt-in narrowing (`scope: explicit_methods`) only.
4. Prescriptive mode is explicit opt-in:
   - requires declared canonical value,
   - requires proposal + approval + apply workflow.
5. Keep non-profile tools behaviorally unchanged (tolerant interfaces remain default).
6. Preserve deterministic, typed diagnostics for every continuity decision.
7. Remove legacy methods-first schema paths in runtime/docs/tests; do not dual-run both shapes.

## Prerequisites and Dependencies

Already available:

1. ADR 0023 reliability scorecards and lifecycle states.
2. ADR 0025 awareness substrate, proposal artifacts, and authority gates.
3. Existing recoverable guardrail retry lanes (ADR 0014/0016).

Dependency rule:

1. ADR 0024 enforcement paths must call ADR 0025 authority checks for any profile mutation.
2. Continuity checks run in validation lanes; mutation authority remains outside hot-path runtime decisions.

## Ubiquitous Language Deliverables

Add/confirm these UL terms in [`docs/ubiquitous-language.md`](../ubiquitous-language.md) and use them consistently in code/docs/logs:

1. `Role Profile`
2. `State Continuity`
3. `State Continuity Guard`
4. `Coordination Constraint`
5. `Prescriptive Constraint`
6. `Profile Compliance`
7. `Profile Drift`
8. `Active Profile Version`
9. `Profile Lifecycle Proposal`

## Delivery Strategy

Deliver in seven phases with hard exit gates and evidence artifacts.

### Phase 0: Contract Freeze and Baseline

Goals:

1. Freeze profile schema and continuity report contract.
2. Freeze coordination vs prescriptive semantics.
3. Capture baseline behavior before continuity logic affects execution.
4. Freeze clean-break policy for schema removal.

Implementation:

1. Define/confirm canonical schema for:
   - `RoleProfile`
   - `ConstraintDefinition`
   - `ProfileComplianceReport`
   - `role_profile_update` proposal artifact payload
   - scope semantics (`all_methods`, `explicit_methods`, `exclude_methods`)
2. Document active-profile binding rule per call.
3. Capture baseline traces for:
   - calculator flow,
   - assistant flow,
   - one known continuity-drift scenario.
4. Document removal plan for methods-first shape from runtime/docs/tests.

Suggested files:

1. [`docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md`](../adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md)
2. [`docs/ubiquitous-language.md`](../ubiquitous-language.md)
3. [`docs/observability.md`](../observability.md)
4. `docs/baselines/<date>/adr-0024-phase0/`

Phase Improvement Contract:

1. Baseline snapshot: pre-ADR-0024 traces with no typed continuity evidence.
2. Expected delta: baseline evidence is captured and indexed with known drift exemplars.
3. Observed delta: to be recorded in `docs/baselines/<date>/adr-0024/phase-0-validation.md`.

Exit criteria:

1. Schema fields and semantics are unambiguous.
2. Baseline traces are stored and indexed.
3. UL terms added/updated.
4. Removal targets for methods-first shape are enumerated.

### Phase 1: RoleProfile Runtime Contract and Registry

Goals:

1. Introduce runtime-readable role profiles with explicit versioning.
2. Enforce scope-first schema (`scope` required/defaulted to `all_methods`).
3. Remove legacy methods-first parsing and persistence shape.

Implementation:

1. Add profile model and validation:
   - required fields (`role`, `version`, `constraints`),
   - mode validation (`coordination`, `prescriptive`),
   - scope validation (`all_methods` or `explicit_methods`),
   - prescriptive canonical value requirements.
2. Add profile registry/store and lookup API.
3. Bind calls to one active profile version and emit binding metadata.
4. Ensure profile absence is first-class (`nil`/unset path remains valid).
5. Remove/replace methods-first examples, fixtures, and stored artifacts in test setup.

Suggested files:

1. [`runtimes/ruby/lib/recurgent/role_profile.rb`](../../runtimes/ruby/lib/recurgent/role_profile.rb) (new)
2. [`runtimes/ruby/lib/recurgent/role_profile_registry.rb`](../../runtimes/ruby/lib/recurgent/role_profile_registry.rb) (new)
3. [`runtimes/ruby/lib/recurgent/call_state.rb`](../../runtimes/ruby/lib/recurgent/call_state.rb)
4. [`runtimes/ruby/lib/recurgent/observability.rb`](../../runtimes/ruby/lib/recurgent/observability.rb)
5. `runtimes/ruby/spec/...` (unit + acceptance)

Phase Improvement Contract:

1. Baseline snapshot: role profile version is not bound as explicit call metadata.
2. Expected delta: profile-enabled calls record deterministic active-profile binding while non-profile calls remain unchanged.
3. Observed delta: to be recorded in `docs/baselines/<date>/adr-0024/phase-1-validation.md`.

Exit criteria:

1. Runtime can resolve and bind active profile version when configured.
2. Non-profile agents execute unchanged.
3. Observability includes profile-binding metadata.
4. Methods-first schema inputs fail fast.

### Phase 2: Continuity Evaluator in Shadow Mode

Goals:

1. Compute continuity compliance without affecting outcomes.
2. Generate correction hints and structured drift diagnostics.

Implementation:

1. Implement continuity evaluator:
   - shared state slot coherence,
   - method-family return-shape coherence,
   - signature-family coherence.
2. Implement mode-aware checks:
   - coordination: agreement across sibling observations,
   - prescriptive: agreement with canonical values.
3. Implement scope-aware sibling set resolution:
   - `all_methods`: include all observed role methods by default,
   - apply `exclude_methods` carve-outs,
   - `explicit_methods`: include only listed methods.
4. Emit structured shadow results:
   - pass/fail by constraint,
   - violation reason,
   - suggested correction hint.
5. Persist per-attempt continuity evidence for later rollout tuning.

Suggested files:

1. [`runtimes/ruby/lib/recurgent/role_profile_guard.rb`](../../runtimes/ruby/lib/recurgent/role_profile_guard.rb) (new)
2. [`runtimes/ruby/lib/recurgent/observability.rb`](../../runtimes/ruby/lib/recurgent/observability.rb)
3. [`runtimes/ruby/lib/recurgent/observability_attempt_fields.rb`](../../runtimes/ruby/lib/recurgent/observability_attempt_fields.rb)
4. `runtimes/ruby/spec/...`

Phase Improvement Contract:

1. Baseline snapshot: semantic drift is not represented as typed continuity findings.
2. Expected delta: drift is observable as structured continuity shadow findings with actionable hints.
3. Observed delta: to be recorded in `docs/baselines/<date>/adr-0024/phase-2-validation.md`.

Exit criteria:

1. Shadow reports are deterministic and human-explainable.
2. No execution blocking occurs in this phase.
3. Violations and hints appear in logs for profile-enabled calls.
4. Newly forged methods are automatically included under `all_methods` constraints.

### Phase 3: Coordination Enforcement via Recoverable Lanes

Goals:

1. Enforce coordination constraints through existing recoverable guardrail paths.
2. Preserve tolerant behavior via retries and correction hints.

Implementation:

1. Raise typed recoverable continuity violation for coordination failures.
2. Route violations through existing retry budget and regeneration logic.
3. Attach deterministic correction hints to regeneration prompts.
4. Keep non-profile and shadow-disabled paths unchanged.
5. Verify recoverable enforcement on forged methods not predeclared in profiles.

Suggested files:

1. [`runtimes/ruby/lib/recurgent/call_execution.rb`](../../runtimes/ruby/lib/recurgent/call_execution.rb)
2. [`runtimes/ruby/lib/recurgent/outcome.rb`](../../runtimes/ruby/lib/recurgent/outcome.rb)
3. [`runtimes/ruby/lib/recurgent/observability.rb`](../../runtimes/ruby/lib/recurgent/observability.rb)
4. `runtimes/ruby/spec/...`

Phase Improvement Contract:

1. Baseline snapshot: coordination drift can pass as apparent success.
2. Expected delta: coordination drift triggers recoverable continuity guardrails and retry-based repair attempts.
3. Observed delta: to be recorded in `docs/baselines/<date>/adr-0024/phase-3-validation.md`.

Exit criteria:

1. Coordination violations trigger recoverable retries, not immediate terminal failures.
2. Logs show violation type, correction hint, retry path, and final outcome.
3. Calculator continuity drift class is reduced in phase evidence.

### Phase 4: Profile Lifecycle Governance Integration

Goals:

1. Enforce ADR 0025 governance for all profile lifecycle mutations.
2. Ensure profile updates are explicit, auditable, and reviewable.

Implementation:

1. Encode profile lifecycle changes as `role_profile_update` proposals.
2. Gate creation/version bump/mode change/apply through authority checks.
3. Emit typed `authority_denied` on unauthorized mutation attempts.
4. Add operator review/apply workflow docs and examples.
5. Require scope-first contract payloads in `role_profile_update` proposals.

Suggested files:

1. [`runtimes/ruby/lib/recurgent/proposal_store.rb`](../../runtimes/ruby/lib/recurgent/proposal_store.rb)
2. [`runtimes/ruby/lib/recurgent/authority.rb`](../../runtimes/ruby/lib/recurgent/authority.rb)
3. [`docs/governance.md`](../governance.md)
4. [`docs/maintenance.md`](../maintenance.md)

Phase Improvement Contract:

1. Baseline snapshot: profile lifecycle governance paths are not fully standardized.
2. Expected delta: all role-profile mutations flow through proposal + authority lanes with complete auditability.
3. Observed delta: to be recorded in `docs/baselines/<date>/adr-0024/phase-4-validation.md`.

Exit criteria:

1. No direct profile mutation path bypasses proposal + authority lanes.
2. End-to-end proposal approval/apply flow works for role profile updates.
3. Audit trail is complete for profile lifecycle operations.

### Phase 5: Prescriptive Constraints and Versioned Activation

Goals:

1. Add optional deterministic constraints where needed.
2. Keep prescriptive usage deliberate and narrow.

Implementation:

1. Enable prescriptive checks for selected constraints only.
2. Require explicit canonical values and active version selection.
3. Add migration path for profile version bumps and rollback.
4. Add guardrails preventing accidental coordination->prescriptive drift without approved proposal.
5. Keep prescriptive constraints scope-first by default; use explicit narrowing only when justified.

Suggested files:

1. [`runtimes/ruby/lib/recurgent/role_profile_guard.rb`](../../runtimes/ruby/lib/recurgent/role_profile_guard.rb)
2. [`runtimes/ruby/lib/recurgent/role_profile_registry.rb`](../../runtimes/ruby/lib/recurgent/role_profile_registry.rb)
3. `runtimes/ruby/spec/...`
4. [`docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md`](../adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md)

Phase Improvement Contract:

1. Baseline snapshot: only coordination expectations are enforced.
2. Expected delta: selected deterministic constraints are enforceable via explicit prescriptive mode and versioned activation.
3. Observed delta: to be recorded in `docs/baselines/<date>/adr-0024/phase-5-validation.md`.

Exit criteria:

1. Prescriptive constraints pass only when canonical values are met.
2. Version switch and rollback are deterministic and audited.
3. Coordination-only roles remain unaffected.

### Phase 6: Promotion Coupling and Rollout Hardening

Goals:

1. Couple profile compliance evidence into durable eligibility for profile-enabled roles.
2. Keep reliability-only policy for non-profile tools.

Implementation:

1. Add profile-compliance input to durability gate logic.
2. Define initial thresholds:
   - minimum observation window: `>= 10` calls across `>= 2` sessions,
   - global defaults first,
   - specialization trigger when class false-hold/false-promotion > `2x` global rate.
3. Add coherence signal in scorecard for sibling-state agreement (`state_key_consistency_ratio`).
4. Publish rollout metrics and tuning notes.
5. Ensure promotion metrics consume scope-resolved continuity evidence (including newly forged methods).

### Phase 7: Removal and Cleanup (Schema Hard Cut)

Goals:

1. Remove all methods-first profile shape references from runtime/docs/tests.
2. Remove transitional helpers/fixtures used only for dual-shape support.
3. Validate repository only emits scope-first role-profile contracts.

Implementation:

1. Delete methods-first parsing branches and tests.
2. Rewrite examples/docs/snippets to scope-first contracts.
3. Purge or regenerate stale baseline fixtures that encode old profile shape.
4. Add lint/spec guard that forbids methods-first role-profile examples in repo docs.

Exit criteria:

1. No runtime code path accepts methods-first as default schema.
2. No docs/examples show methods-first coordination as baseline.
3. CI/spec guard fails if methods-first profile snippets reappear.

Suggested files:

1. `runtimes/ruby/lib/recurgent/promotion_policy.rb`
2. `runtimes/ruby/lib/recurgent/tool_scorecard.rb`
3. [`runtimes/ruby/lib/recurgent/observability.rb`](../../runtimes/ruby/lib/recurgent/observability.rb)
4. [`docs/observability.md`](../observability.md)

Phase Improvement Contract:

1. Baseline snapshot: durable eligibility is reliability-only for all artifacts.
2. Expected delta: profile-enabled roles require reliability + continuity compliance; non-profile tools remain reliability-only.
3. Observed delta: to be recorded in `docs/baselines/<date>/adr-0024/phase-6-validation.md`.

Exit criteria:

1. Profile-enabled roles require both reliability and continuity compliance for durable eligibility.
2. Non-profile tools remain reliability-only.
3. False-hold/false-promotion metrics are visible and reviewable.

## Validation Protocol (Mandatory at End of Every Phase)

Run and archive results for each phase:

1. Entire test suite (`bundle exec rspec`).
2. Calculator example ([`runtimes/ruby/examples/calculator.rb`](../../runtimes/ruby/examples/calculator.rb)) and verify arithmetic outputs.
3. Personal assistant example ([`runtimes/ruby/examples/assistant.rb`](../../runtimes/ruby/examples/assistant.rb)) with prompts:
   - `What's the top news items in Google News, Yahoo! News, and NY Times`
   - `What's are the action adventure movies playing in theaters`
   - `What's a good recipe for Jaffna Kool`
4. Log and trace review after calculator and assistant runs:
   - exact execution path,
   - output accuracy assessment,
   - what improved,
   - what regressed,
   - next remediation action.

Evidence location convention:

1. `docs/baselines/<date>/adr-0024/phase-<n>-validation.md`
2. `docs/baselines/<date>/adr-0024/logs/phase-<n>-*.jsonl`

## Test Strategy

1. Unit tests:
   - profile schema/mode validation,
   - continuity evaluator behavior per constraint kind/mode,
   - authority checks on profile lifecycle actions.
2. Integration tests:
   - shadow-mode reporting,
   - recoverable continuity retries,
   - proposal approve/apply profile lifecycle flow.
3. Acceptance tests:
   - calculator role continuity,
   - assistant role behavior under profile/no-profile modes.
4. Regression tests:
   - non-profile tools remain behaviorally unchanged,
   - tolerant interface behavior preserved.

## Risk Register and Mitigations

1. Risk: over-prescription blocks evolution.
   Mitigation: coordination default + explicit approval required for prescriptive mode.
2. Risk: shadow false positives overwhelm logs.
   Mitigation: deterministic extraction, thresholded reporting, and tune before enforcement.
3. Risk: hidden profile mutation paths bypass authority.
   Mitigation: centralize lifecycle operations behind authority-gated service.
4. Risk: promotion coupling causes premature holds.
   Mitigation: minimum observation window + shadow ledger calibration.
5. Risk: complexity drift in role contracts.
   Mitigation: keep constraint kinds minimal; expand only with evidence.

## Completion Criteria

ADR 0024 is complete when all are true:

1. Role profiles are opt-in, versioned, and authority-governed.
2. Continuity drift is visible in shadow and recoverable in enforcement.
3. Coordination mode works as environmental pressure without dictating canonical values.
4. Prescriptive mode is available but explicitly controlled.
5. Promotion for profile-enabled roles uses both reliability and profile-compliance evidence.
6. UL/docs/tests/trace artifacts are updated and internally consistent.
7. Methods-first profile schema has been removed from runtime/docs/tests (clean cut complete).
