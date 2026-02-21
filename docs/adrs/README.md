# Architecture Decision Records

This directory captures architecture decisions that shape Recurgent's runtime behavior and maintenance model.

## Required Outcome Sections

Every new ADR must include these sections to make expected impact testable:

1. `Status Quo Baseline`
2. `Expected Improvements` (with measurable deltas)
3. `Non-Improvement Expectations` (what should stay unchanged)
4. `Validation Signals` (tests/traces/log fields and thresholds)
5. `Rollback or Adjustment Triggers`

Use [`docs/adrs/TEMPLATE.md`](TEMPLATE.md) for new ADRs.

## Index

- [`0001-core-dispatch-via-method-missing.md`](0001-core-dispatch-via-method-missing.md)
- [`0002-provider-abstraction-and-model-routing.md`](0002-provider-abstraction-and-model-routing.md)
- [`0003-error-handling-contract.md`](0003-error-handling-contract.md)
- [`0004-llm-native-coordination-surface.md`](0004-llm-native-coordination-surface.md)
- [`0005-project-name-transition-to-recurgent.md`](0005-project-name-transition-to-recurgent.md)
- [`0006-monorepo-runtime-boundaries.md`](0006-monorepo-runtime-boundaries.md)
- [`0007-runtime-agnostic-contract-spec.md`](0007-runtime-agnostic-contract-spec.md)
- [`0008-tool-builder-tool-language-and-tolerant-delegations.md`](0008-tool-builder-tool-language-and-tolerant-delegations.md)
- [`0009-issue-first-pr-compliance-gate.md`](0009-issue-first-pr-compliance-gate.md)
- [`0010-dependency-aware-generated-programs-and-environment-contract-v1.md`](0010-dependency-aware-generated-programs-and-environment-contract-v1.md)
- [`0011-env-cache-policy-and-effective-manifest-execution.md`](0011-env-cache-policy-and-effective-manifest-execution.md)
- [`0012-cross-session-tool-persistence-and-evolutionary-artifact-selection.md`](0012-cross-session-tool-persistence-and-evolutionary-artifact-selection.md)
- [`0013-cacheability-gating-and-pattern-memory-for-tool-promotion.md`](0013-cacheability-gating-and-pattern-memory-for-tool-promotion.md)
- [`0014-outcome-boundary-contract-validation-and-tolerant-interface-canonicalization.md`](0014-outcome-boundary-contract-validation-and-tolerant-interface-canonicalization.md)
- [`0015-tool-self-awareness-and-boundary-referral-for-emergent-tool-evolution.md`](0015-tool-self-awareness-and-boundary-referral-for-emergent-tool-evolution.md)
- [`0016-validation-first-fresh-generation-and-transactional-guardrail-recovery.md`](0016-validation-first-fresh-generation-and-transactional-guardrail-recovery.md)
- [`0017-contract-driven-utility-failures-and-observational-runtime.md`](0017-contract-driven-utility-failures-and-observational-runtime.md)
- [`0018-contextview-and-recursive-context-exploration-v1.md`](0018-contextview-and-recursive-context-exploration-v1.md)
- [`0019-structured-conversation-history-first-and-recursion-deferral.md`](0019-structured-conversation-history-first-and-recursion-deferral.md)
- [`0020-generated-code-execution-sandbox-isolation.md`](0020-generated-code-execution-sandbox-isolation.md)
- [`0021-external-data-provenance-invariant.md`](0021-external-data-provenance-invariant.md)
- [`0022-guardrail-exhaustion-boundary-normalization.md`](0022-guardrail-exhaustion-boundary-normalization.md)
- [`0023-solver-shape-and-reliability-gated-tool-evolution.md`](0023-solver-shape-and-reliability-gated-tool-evolution.md)
- [`0024-contract-first-role-profiles-and-state-continuity-guard.md`](0024-contract-first-role-profiles-and-state-continuity-guard.md)
- [`0025-awareness-substrate-and-authority-boundary.md`](0025-awareness-substrate-and-authority-boundary.md)
- [`0026-response-content-continuity-substrate.md`](0026-response-content-continuity-substrate.md)
- [`TEMPLATE.md`](TEMPLATE.md)

## Status Values

- `accepted`
- `superseded`
- `proposed`
