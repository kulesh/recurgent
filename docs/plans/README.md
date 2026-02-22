# Implementation Plans

This directory contains phased implementation plans that operationalize ADRs and major roadmap slices.

## Required Outcome Sections

Every new implementation plan must include:

1. `Status Quo Baseline`
2. `Expected Improvements` (measurable deltas from baseline)
3. `Non-Improvement Expectations`
4. `Validation Signals and Thresholds`
5. `Rollback or Adjustment Triggers`

In addition, every phase section must include a `Phase Improvement Contract`:

1. baseline snapshot,
2. expected delta,
3. observed delta after validation run.

Use [`docs/plans/TEMPLATE.md`](TEMPLATE.md) for new implementation plans.

## Core Runtime Evolution

- [`recurgent-implementation-plan.md`](recurgent-implementation-plan.md) - LLM-native coordination API and naming transition
- [`dependency-environment-implementation-plan.md`](dependency-environment-implementation-plan.md) - dependency-aware generated programs and environment contracts
- [`cross-session-tool-persistence-implementation-plan.md`](cross-session-tool-persistence-implementation-plan.md) - tool/artifact persistence lifecycle
- [`cacheability-pattern-memory-implementation-plan.md`](cacheability-pattern-memory-implementation-plan.md) - cacheability gating and pattern-memory promotion
- [`solver-shape-reliability-gated-tool-evolution-implementation-plan.md`](solver-shape-reliability-gated-tool-evolution-implementation-plan.md) - solver-shape evidence + reliability-gated lifecycle rollout

## Contract and Boundary Hardening

- [`outcome-boundary-contract-validation-implementation-plan.md`](outcome-boundary-contract-validation-implementation-plan.md) - delegated outcome contract enforcement
- [`tool-self-awareness-boundary-referral-implementation-plan.md`](tool-self-awareness-boundary-referral-implementation-plan.md) - `wrong_tool_boundary` and `low_utility` evolution loop
- [`validation-first-fresh-generation-implementation-plan.md`](validation-first-fresh-generation-implementation-plan.md) - validation-first retries with transactional isolation
- [`contract-driven-utility-failures-implementation-plan.md`](contract-driven-utility-failures-implementation-plan.md) - utility semantics at contract boundary
- [`guardrail-exhaustion-boundary-normalization-implementation-plan.md`](guardrail-exhaustion-boundary-normalization-implementation-plan.md) - top-level guardrail exhaustion normalization
- [`contract-first-role-profiles-state-continuity-implementation-plan.md`](contract-first-role-profiles-state-continuity-implementation-plan.md) - role-profile coordination semantics, continuity guard rollout, and promotion coupling

## Context, Execution, and Telemetry

- [`structured-conversation-history-implementation-plan.md`](structured-conversation-history-implementation-plan.md) - structured history-first rollout
- [`generated-code-execution-sandbox-isolation-implementation-plan.md`](generated-code-execution-sandbox-isolation-implementation-plan.md) - per-attempt sandbox receiver isolation
- [`external-data-provenance-implementation-plan.md`](external-data-provenance-implementation-plan.md) - provenance invariants and enforcement
- [`failed-attempt-exception-telemetry-implementation-plan.md`](failed-attempt-exception-telemetry-implementation-plan.md) - preserve failed-attempt diagnostics in logs/artifacts
- [`awareness-substrate-authority-boundary-implementation-plan.md`](awareness-substrate-authority-boundary-implementation-plan.md) - bounded awareness rollout with explicit observe/propose/enact authority gates
- [`response-content-continuity-implementation-plan.md`](response-content-continuity-implementation-plan.md) - bounded response-content store, history content references, and follow-up retrieval reliability
- [`simulation-preparedness-implementation-plan.md`](simulation-preparedness-implementation-plan.md) - readiness-gated simulation rollout (`G0`-`G5`) with replay, schema, baseline-diff, and CI enforcement
- [`TEMPLATE.md`](TEMPLATE.md) - canonical implementation-plan structure with measurable outcome contracts
