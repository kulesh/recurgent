# ADR 0027 Validation Rollup (Phases 0-6)

- Date: 2026-02-22
- Source artifacts:
  - [`docs/baselines/2026-02-22/adr-0027/phase-0-validation.md`](../baselines/2026-02-22/adr-0027/phase-0-validation.md)
  - [`docs/baselines/2026-02-22/adr-0027/phase-1-validation.md`](../baselines/2026-02-22/adr-0027/phase-1-validation.md)
  - [`docs/baselines/2026-02-22/adr-0027/phase-2-validation.md`](../baselines/2026-02-22/adr-0027/phase-2-validation.md)
  - [`docs/baselines/2026-02-22/adr-0027/phase-3-validation.md`](../baselines/2026-02-22/adr-0027/phase-3-validation.md)
  - [`docs/baselines/2026-02-22/adr-0027/phase-4-validation.md`](../baselines/2026-02-22/adr-0027/phase-4-validation.md)
  - [`docs/baselines/2026-02-22/adr-0027/phase-5-validation.md`](../baselines/2026-02-22/adr-0027/phase-5-validation.md)
  - [`docs/baselines/2026-02-22/adr-0027/phase-6-validation.md`](../baselines/2026-02-22/adr-0027/phase-6-validation.md)

## Scope

This rollup evaluates [ADR-0027](../adrs/0027-simulation-preparedness-and-readiness-gates.md) implementation against the declared outcomes:

1. class-1 simulation governed by explicit readiness gates (`G0`-`G5`),
2. replayable/diffable/schema-valid run evidence,
3. CI/nightly operationalization with machine-checkable reporting.

## Execution Summary

- Full suite remained green in every phase:
  - RuboCop: `92 -> 107 files`, `0 offenses` each phase.
  - RSpec: `275 -> 290 examples`, `0 failures` each phase.
- Gate progression by phase:
  - Phase 0: contract + ledger schemas established.
  - Phase 1: `G0` scenario-pack validation active.
  - Phase 2: `G1` replayability active (`replay_stability=1.0` on pilot runs).
  - Phase 3: `G2` deterministic score reproducibility active (`advisory -> pass` on comparable replay).
  - Phase 4: `G3` trace-schema gate active (`pass` on valid stream, `fail` on malformed stream).
  - Phase 5: `G4` baseline-diff report guaranteed (`no_baseline`, `unchanged` classifications observed).
  - Phase 6: `G5` operationalization active (`ci` and nightly expanded-seed runs both pass when fixture warmup matches replay seeds).

## What Improved

1. Simulation readiness moved from prose to enforceable contracts.
   - Machine-readable schemas now define gate semantics, scenario packs, and ledger evidence.
2. Determinism infrastructure is now testable and reusable.
   - Fixture/replay pipeline, scorer reproducibility, and baseline diff outputs are all persisted and auditable.
3. Trace integrity became a hard gate instead of manual inspection.
   - Invalid trace streams now fail with exact index/path diagnostics.
4. Operational readiness is wired into automation.
   - Added CI class-1 gate workflow and nightly expanded-seed workflow with artifact publication.
5. Documentation now reflects operator reality.
   - Simulation ops guide and release checklist include readiness-gate expectations.

## What Did Not Improve (or Stayed Variable)

1. Calculator semantic stability is still incomplete.
   - `history` remained unstable (`guardrail_retry_exhausted`) through all phases.
   - Arithmetic/solve correctness improved in some phases but regressed intermittently in others.
2. Assistant external-data behavior remains source-dependent.
   - News can be partial due upstream fetch/parse differences (for example Google feed empty body).
   - Movies remains correctly boundary-limited (`capability_unavailable`) due no theater API capability.
   - Recipe handling varies by run/provider/tooling path; latest phase returned capability boundary instead of concrete recipe.
3. Observation-window criteria are not yet satisfied.
   - ADR target requires `20` consecutive class-1 runs across `>= 5` seeds, `>= 2` sessions, and `>= 3` days.
   - Current implementation has infrastructure for this, but not yet enough longitudinal evidence.

## Expected vs Observed

1. Expected: replay stability >= 99% for class-1 fixture/replay.
   - Observed: achieved when fixture and replay seeds match; deterministic failure appears immediately when replay seed set exceeds warmed fixtures.
2. Expected: score reproducibility 100% for same seed/config.
   - Observed: achieved (`G2=pass`) once comparable replay baseline exists.
3. Expected: schema-valid trace enforcement for simulation runs.
   - Observed: achieved (`G3` pass/fail behavior validated with targeted malformed input).
4. Expected: baseline diff report for every class-1 run.
   - Observed: achieved in phase 5 onward.
5. Expected: CI/nightly operational gates.
   - Observed: implemented; local emulation confirms `G5` semantics and workflow-compatible execution path.

## Core Learnings

1. Readiness infrastructure now reliably measures quality signals; it does not itself repair runtime semantics.
2. Seed/fixture parity is a hard precondition for replayability and must be explicit in nightly automation.
3. Gate sequencing from [ADR-0027](../adrs/0027-simulation-preparedness-and-readiness-gates.md) is correct in practice:
   - `G0` before `G2` (score consistency only meaningful with explicit oracles),
   - `G1` before `G4` (diffs are only actionable under deterministic replay conditions).
4. Example instability is now easier to classify:
   - deterministic semantic drift (calculator/history),
   - boundary-correct capability gaps (movies),
   - upstream/external variability (news feeds).

## Readiness Conclusion

[ADR-0027](../adrs/0027-simulation-preparedness-and-readiness-gates.md) implementation is complete for Phase 0-6 feature scope. Recurgent now has a functional readiness-gate substrate (`G0`-`G5`) with contracts, runner support, and CI/nightly operational hooks.

Project state is now suitable to begin disciplined simulation-driven iteration, with one caveat: semantic improvements still require targeted runtime/tool/profile work; the simulation stack provides evidence and regression pressure, not automatic semantic correction.

## Recommended Next Steps

1. Start the [ADR-0027](../adrs/0027-simulation-preparedness-and-readiness-gates.md) observation window protocol (20+ class-1 runs across 3+ days) and publish a run-health dashboard snapshot.
2. Add a deterministic calculator-history scenario pack to make the persistent `history` failure an explicit scored regression.
3. Add fixture-backed assistant packs (news/recipe variants) to separate external drift from runtime/tool behavior in class-2 advisory runs.
