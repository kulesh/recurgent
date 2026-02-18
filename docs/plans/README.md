# Implementation Plans

This directory contains phased implementation plans that operationalize ADRs and major roadmap slices.

## Core Runtime Evolution

- `recurgent-implementation-plan.md` - LLM-native coordination API and naming transition
- `dependency-environment-implementation-plan.md` - dependency-aware generated programs and environment contracts
- `cross-session-tool-persistence-implementation-plan.md` - tool/artifact persistence lifecycle
- `cacheability-pattern-memory-implementation-plan.md` - cacheability gating and pattern-memory promotion

## Contract and Boundary Hardening

- `outcome-boundary-contract-validation-implementation-plan.md` - delegated outcome contract enforcement
- `tool-self-awareness-boundary-referral-implementation-plan.md` - `wrong_tool_boundary` and `low_utility` evolution loop
- `validation-first-fresh-generation-implementation-plan.md` - validation-first retries with transactional isolation
- `contract-driven-utility-failures-implementation-plan.md` - utility semantics at contract boundary
- `guardrail-exhaustion-boundary-normalization-implementation-plan.md` - top-level guardrail exhaustion normalization

## Structural and Philosophy Adherence

- `philosophy-adherence-implementation-plan.md` - module consolidation, test decomposition, prompt tightening, defect fixes

## Context, Execution, and Telemetry

- `structured-conversation-history-implementation-plan.md` - structured history-first rollout
- `generated-code-execution-sandbox-isolation-implementation-plan.md` - per-attempt sandbox receiver isolation
- `external-data-provenance-implementation-plan.md` - provenance invariants and enforcement
- `failed-attempt-exception-telemetry-implementation-plan.md` - preserve failed-attempt diagnostics in logs/artifacts

