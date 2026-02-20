# ADR 0024 Validation Rollup (Phases 0-6)

- Date: 2026-02-20
- Source artifacts: `docs/baselines/2026-02-20/adr-0024/phase-*-validation.md`, [`docs/baselines/2026-02-20/adr-0024/phase-rollup.json`](../baselines/2026-02-20/adr-0024/phase-rollup.json)

## Scope

This rollup evaluates ADR-0024 implementation phases against expected improvements from the implementation plan:

1. explicit role-profile contract binding,
2. continuity drift observability and recoverable enforcement,
3. governance integration for profile lifecycle,
4. prescriptive/versioned profile support,
5. promotion coupling with profile-compliance evidence.

## Execution Summary

- Full test suite: passed in every phase run (Phase 0: 249 examples; Phase 1: 252; Phase 2: 253; Phase 3-6: 259).
- Calculator example accuracy by phase:
  - Pass: Phases 2, 3
  - Regressions observed: Phases 1, 4, 5, 6
- Assistant example accuracy by phase:
  - Full expected behavior: Phases 0, 1, 2, 4, 5, 6
  - Partial degradation: Phase 3 (missing Yahoo coverage in first response)

## What Improved

1. Role profile became first-class runtime data.
   - Active profile version is now represented in call state/observability.
   - Registry supports persisted versions and active-version selection.
2. Continuity guard is integrated with recoverable lanes.
   - Coordination and prescriptive constraints are evaluated.
   - Enforced violations route through retry feedback with deterministic correction hints.
3. Governance lifecycle is connected to ADR-0025 authority/proposal lanes.
   - Approved `role_profile_update` proposals can publish, activate, and rollback profiles.
   - Applied mutations are persisted and auditable.
4. Promotion coupling now consumes profile-compliance evidence.
   - Artifact scorecards include role-profile observation and pass-rate metrics.
   - Durable gate applies profile pass-rate threshold only for profile-enabled artifacts.

## What Did Not Improve (or Regressed)

1. Calculator correctness is still unstable across phases.
   - Regressions observed in state continuity outcomes:
     - Phase 4: `sqrt(latest_result)` returned `0.0` with expected `5.656854...`.
     - Phase 5: `multiply(4)` returned `0`, runtime context drifted to `8`.
     - Phase 6: runtime context drift remained (`8` vs expected `32`).
2. Assistant movie query remains unavailable.
   - This is expected capability boundary behavior (`capability_unavailable`) and not an ADR-0024 regression.
3. News aggregation remains variable under live retrieval conditions.
   - Phase 3 had partial coverage.
   - Latest Phase 6 run produced source-specific failures for Google News and Yahoo paths while NYT succeeded.

## Core Diagnosis

1. Promotion and continuity infrastructure improves observability and recovery mechanics, but does not define semantics by itself.
2. Calculator example still runs without an explicit active role profile, so continuity constraints are not reliably shaping generated behavior in that flow.
3. The remaining calculator drift matches the known class: sibling methods can still diverge on state key conventions unless a role profile is explicitly active for that role/session.
4. Assistant news variability is mostly external/live-source/tooling fragility rather than role-profile semantics.

## Expected vs Observed

1. Expected: role-profile-enabled flows should reduce silent continuity drift.
   - Observed: true in enforcement tests/specs; inconsistent in calculator example due profile adoption gap.
2. Expected: profile lifecycle changes should be authority-gated and auditable.
   - Observed: achieved via proposal approve/apply flow with persisted role-profile history.
3. Expected: profile-enabled artifacts should require reliability + continuity for durable eligibility.
   - Observed: implemented and validated by targeted lifecycle tests.

## Key Learning

The implementation delivered the ADR-0024 substrate, but example-level correctness improvements depend on explicit profile adoption in runtime flows. Reliability gates and observability are necessary but insufficient for semantic correctness without active role contracts.

## Recommended Follow-on Remediation

1. Make calculator example explicitly role-profile-enabled (publish/activate profile before arithmetic calls).
2. Add calculator acceptance spec that requires continuity-constrained arithmetic invariants under active profile.
3. Harden news-fetch tool path handling for source URL normalization and request-uri safety to reduce non-semantic live-data failures.
