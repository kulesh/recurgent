# Documentation Index

This index is organized for fast retrieval:

1. Start with orientation docs.
2. Use architecture/ADR docs for design intent and current mechanics.
3. Use plan docs for phased delivery details.

## Start Here

- [`docs/architecture.md`](architecture.md) - canonical runtime architecture and lifecycle diagrams
- [`docs/onboarding.md`](onboarding.md) - setup, workflow, quality gates
- [`docs/ubiquitous-language.md`](ubiquitous-language.md) - canonical Tool Builder/Tool vocabulary
- [`docs/observability.md`](observability.md) - log schema, trace model, and live watcher usage
- [`docs/adrs/README.md`](adrs/README.md) - architecture decision index
- [`docs/adrs/TEMPLATE.md`](adrs/TEMPLATE.md) - ADR template with baseline, expected-improvement, validation, and rollback sections
- [`docs/plans/TEMPLATE.md`](plans/TEMPLATE.md) - implementation-plan template with phase-level improvement contracts

## Product and Specs

- [`docs/specs/idea-brief.md`](specs/idea-brief.md) - mission and product framing
- [`docs/specs/delegation-contracts.md`](specs/delegation-contracts.md) - delegation contract fields and behavior
- [`docs/specs/recursim-product-spec.md`](specs/recursim-product-spec.md) - Recursim product specification
- [`docs/tolerant-delegation-interfaces.md`](tolerant-delegation-interfaces.md) - tolerant interface guidance
- [`docs/delegate-vs-for.md`](delegate-vs-for.md) - `delegate(...)` vs `Agent.for(...)` decision guide

## Tutorials

- [`docs/tutorials/README.md`](tutorials/README.md) - tutorial map
- [`docs/tutorials/personal-assistant-progressive.md`](tutorials/personal-assistant-progressive.md) - progressive walkthrough from minimal assistant to profile-aware, observable, governed runtime behavior

## Architecture Decisions

- [`docs/adrs/0001-core-dispatch-via-method-missing.md`](adrs/0001-core-dispatch-via-method-missing.md)
- [`docs/adrs/0002-provider-abstraction-and-model-routing.md`](adrs/0002-provider-abstraction-and-model-routing.md)
- [`docs/adrs/0003-error-handling-contract.md`](adrs/0003-error-handling-contract.md)
- [`docs/adrs/0004-llm-native-coordination-surface.md`](adrs/0004-llm-native-coordination-surface.md)
- [`docs/adrs/0005-project-name-transition-to-recurgent.md`](adrs/0005-project-name-transition-to-recurgent.md)
- [`docs/adrs/0006-monorepo-runtime-boundaries.md`](adrs/0006-monorepo-runtime-boundaries.md)
- [`docs/adrs/0007-runtime-agnostic-contract-spec.md`](adrs/0007-runtime-agnostic-contract-spec.md)
- [`docs/adrs/0008-tool-builder-tool-language-and-tolerant-delegations.md`](adrs/0008-tool-builder-tool-language-and-tolerant-delegations.md)
- [`docs/adrs/0009-issue-first-pr-compliance-gate.md`](adrs/0009-issue-first-pr-compliance-gate.md)
- [`docs/adrs/0010-dependency-aware-generated-programs-and-environment-contract-v1.md`](adrs/0010-dependency-aware-generated-programs-and-environment-contract-v1.md)
- [`docs/adrs/0011-env-cache-policy-and-effective-manifest-execution.md`](adrs/0011-env-cache-policy-and-effective-manifest-execution.md)
- [`docs/adrs/0012-cross-session-tool-persistence-and-evolutionary-artifact-selection.md`](adrs/0012-cross-session-tool-persistence-and-evolutionary-artifact-selection.md)
- [`docs/adrs/0013-cacheability-gating-and-pattern-memory-for-tool-promotion.md`](adrs/0013-cacheability-gating-and-pattern-memory-for-tool-promotion.md)
- [`docs/adrs/0014-outcome-boundary-contract-validation-and-tolerant-interface-canonicalization.md`](adrs/0014-outcome-boundary-contract-validation-and-tolerant-interface-canonicalization.md)
- [`docs/adrs/0015-tool-self-awareness-and-boundary-referral-for-emergent-tool-evolution.md`](adrs/0015-tool-self-awareness-and-boundary-referral-for-emergent-tool-evolution.md)
- [`docs/adrs/0016-validation-first-fresh-generation-and-transactional-guardrail-recovery.md`](adrs/0016-validation-first-fresh-generation-and-transactional-guardrail-recovery.md)
- [`docs/adrs/0017-contract-driven-utility-failures-and-observational-runtime.md`](adrs/0017-contract-driven-utility-failures-and-observational-runtime.md)
- [`docs/adrs/0018-contextview-and-recursive-context-exploration-v1.md`](adrs/0018-contextview-and-recursive-context-exploration-v1.md)
- [`docs/adrs/0019-structured-conversation-history-first-and-recursion-deferral.md`](adrs/0019-structured-conversation-history-first-and-recursion-deferral.md)
- [`docs/adrs/0020-generated-code-execution-sandbox-isolation.md`](adrs/0020-generated-code-execution-sandbox-isolation.md)
- [`docs/adrs/0021-external-data-provenance-invariant.md`](adrs/0021-external-data-provenance-invariant.md)
- [`docs/adrs/0022-guardrail-exhaustion-boundary-normalization.md`](adrs/0022-guardrail-exhaustion-boundary-normalization.md)
- [`docs/adrs/0023-solver-shape-and-reliability-gated-tool-evolution.md`](adrs/0023-solver-shape-and-reliability-gated-tool-evolution.md)
- [`docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md`](adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md)
- [`docs/adrs/0025-awareness-substrate-and-authority-boundary.md`](adrs/0025-awareness-substrate-and-authority-boundary.md)

## Implementation Plans

- [`docs/plans/README.md`](plans/README.md) - plan map
- [`docs/plans/TEMPLATE.md`](plans/TEMPLATE.md) - plan template
- [`docs/plans/recurgent-implementation-plan.md`](plans/recurgent-implementation-plan.md)
- [`docs/plans/dependency-environment-implementation-plan.md`](plans/dependency-environment-implementation-plan.md)
- [`docs/plans/cross-session-tool-persistence-implementation-plan.md`](plans/cross-session-tool-persistence-implementation-plan.md)
- [`docs/plans/cacheability-pattern-memory-implementation-plan.md`](plans/cacheability-pattern-memory-implementation-plan.md)
- [`docs/plans/outcome-boundary-contract-validation-implementation-plan.md`](plans/outcome-boundary-contract-validation-implementation-plan.md)
- [`docs/plans/tool-self-awareness-boundary-referral-implementation-plan.md`](plans/tool-self-awareness-boundary-referral-implementation-plan.md)
- [`docs/plans/validation-first-fresh-generation-implementation-plan.md`](plans/validation-first-fresh-generation-implementation-plan.md)
- [`docs/plans/contract-driven-utility-failures-implementation-plan.md`](plans/contract-driven-utility-failures-implementation-plan.md)
- [`docs/plans/structured-conversation-history-implementation-plan.md`](plans/structured-conversation-history-implementation-plan.md)
- [`docs/plans/generated-code-execution-sandbox-isolation-implementation-plan.md`](plans/generated-code-execution-sandbox-isolation-implementation-plan.md)
- [`docs/plans/external-data-provenance-implementation-plan.md`](plans/external-data-provenance-implementation-plan.md)
- [`docs/plans/guardrail-exhaustion-boundary-normalization-implementation-plan.md`](plans/guardrail-exhaustion-boundary-normalization-implementation-plan.md)
- [`docs/plans/failed-attempt-exception-telemetry-implementation-plan.md`](plans/failed-attempt-exception-telemetry-implementation-plan.md)
- [`docs/plans/solver-shape-reliability-gated-tool-evolution-implementation-plan.md`](plans/solver-shape-reliability-gated-tool-evolution-implementation-plan.md)
- [`docs/plans/contract-first-role-profiles-state-continuity-implementation-plan.md`](plans/contract-first-role-profiles-state-continuity-implementation-plan.md)
- [`docs/plans/awareness-substrate-authority-boundary-implementation-plan.md`](plans/awareness-substrate-authority-boundary-implementation-plan.md)

## Baselines and Operations

- [`docs/baselines/2026-02-15/README.md`](baselines/2026-02-15/README.md) - baseline trace fixtures
- [`docs/baselines/2026-02-20/adr-0024/phase-rollup.json`](baselines/2026-02-20/adr-0024/phase-rollup.json) - ADR 0024 phase-by-phase validation rollup
- [`docs/reports/adr-0024-phase-validation-rollup.md`](reports/adr-0024-phase-validation-rollup.md) - ADR 0024 expected-vs-observed validation analysis
- [`docs/reports/adr-0024-scope-hardcut-validation-report.md`](reports/adr-0024-scope-hardcut-validation-report.md) - validation report for scope-first role-profile hard cut and required calculator/assistant traces
- [`docs/runtime-configuration.md`](runtime-configuration.md) - runtime configuration reference for dependency policy, lifecycle toggles, toolstore roots, and authority settings
- [`docs/roadmap.md`](roadmap.md) - near/mid/long-term roadmap
- [`docs/maintenance.md`](maintenance.md) - dependency/runtime maintenance policy
- [`docs/release-process.md`](release-process.md) - release process and SemVer policy
- [`docs/open-source-release-checklist.md`](open-source-release-checklist.md) - OSS release checklist
- [`docs/governance.md`](governance.md) - maintainer governance
- [`docs/support.md`](support.md) - support policy

## Repository-Level References

- [`README.md`](../README.md) - mission and project overview
- [`CONTRIBUTING.md`](../CONTRIBUTING.md) - contribution workflow and quality gates
- [`CHANGELOG.md`](../CHANGELOG.md) - release history
- [`SECURITY.md`](../SECURITY.md) - vulnerability reporting
- [`CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md) - collaboration policy
- [`specs/contract/README.md`](../specs/contract/README.md) - runtime-agnostic contract package
- [`specs/contract/v1/agent-contract.md`](../specs/contract/v1/agent-contract.md) - normative behavior contract
- [`specs/contract/v1/scenarios.yaml`](../specs/contract/v1/scenarios.yaml) - shared conformance scenarios
- [`runtimes/ruby/README.md`](../runtimes/ruby/README.md) - Ruby runtime quick reference
- [`runtimes/lua/README.md`](../runtimes/lua/README.md) - Lua runtime placeholder
