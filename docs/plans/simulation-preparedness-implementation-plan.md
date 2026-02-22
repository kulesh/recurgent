# Simulation Preparedness Implementation Plan

- Status: draft
- Date: 2026-02-21
- Scope: ADR 0027 simulation readiness gates and activation policy

## Objective

Operationalize ADR 0027 so automated simulation can be used as a trustworthy evolution/release signal.

Primary outcomes:

1. Class-1 simulation (self-contained, calculator-first) is governed by explicit readiness gates (`G0`-`G5`).
2. Simulation runs are replayable, diffable, schema-valid, and CI-enforced.
3. Simulation output becomes actionable evidence instead of anecdotal output.

## Status Quo Baseline

1. Runtime infrastructure is strong, but scenario semantics remain inconsistent in phase reports (for example calculator regressions despite passing suites).
2. Recursim scope and metrics are documented (`docs/product-specs/recursim-product-spec.md`), but readiness gates are not yet implemented as enforcement.
3. Observability schema/docs now exist (`specs/contract/v1/recurgent-log-*.schema.json`, `docs/observability.md`) but are not integrated into a simulation-gating flow.

## Expected Improvements

1. Replay stability for class-1 fixture runs reaches `>= 99%` identical score vectors on same commit/seed/config.
2. Every class-1 simulation run emits schema-valid logs (`100%` pass against `recurgent-log-stream.schema.json`).
3. Baseline diff report generation coverage reaches `100%` for class-1 runs.
4. CI gate prevents class-1 readiness regressions from merging.

## Non-Improvement Expectations

1. This plan does not directly fix runtime semantics (calculator/news correctness is measured, not auto-repaired).
2. This plan does not relax ADR 0025 authority boundaries (observe/propose/enact separation remains).
3. This plan does not promote class-2+ simulation to gating before class-1 stability window is satisfied.

## Validation Signals and Thresholds

1. Tests/specs:
   - existing Ruby suite must stay green,
   - simulation harness tests for scenario loading, scoring, replay controls, and diff generation.
2. Traces/logs:
   - logs include `trace_id`, `call_id`, `parent_call_id`, `depth`, `outcome_status`,
   - logs validate against `specs/contract/v1/recurgent-log-stream.schema.json`.
3. Thresholds:
   - `G1` replay stability `>= 99%`,
   - `G2` score reproducibility `100%` (same seed/config),
   - `G3` schema validation pass rate `100%`,
   - `G4` baseline diff report generation `100%`,
   - `G5` CI/nightly gating enabled for class-1 packs.
4. Observation window:
   - minimum `20` consecutive class-1 runs across `>= 5` seeds, `>= 2` sessions, and `>= 3` calendar days.

## Rollback or Adjustment Triggers

1. Replay stability `< 95%` for class-1 fixture runs -> freeze scope expansion and remediate determinism leaks.
2. Any schema-validation failure in simulation logs -> fail readiness gate and block readiness claims.
3. Baseline diff noise `> 20%` non-actionable runs -> tighten scenario/oracle contracts before adding more packs.
4. CI flakiness from simulation gate `> 5%` over rolling week -> move gate to advisory while determinism issues are fixed.

## Non-Goals

1. Full implementation of all Recursim classes in one rollout.
2. Autonomous application of simulation recommendations.
3. Replacing existing acceptance and contract suites with simulation-only checks.

## Design Constraints

1. Gate dependencies are sequential:
   - `G0` before `G2`,
   - `G1` before `G4`.
2. Fixture/replay evidence is authoritative for gating; live-network runs are advisory.
3. Scoring weights are scenario-class specific (not one universal profile).
4. Gate decisions must be reproducible from persisted run artifacts and logs.
5. All gate outcomes must be machine-checkable.

## Delivery Strategy

### Phase 0: Readiness Contract and Run Ledger

Goals:

1. Formalize gate contract and gate-evaluation interfaces.
2. Define run ledger schema for simulation evidence.

Implementation:

1. Define `simulation_preparedness` contract file under `specs/contract/v1`.
2. Define run ledger record schema:
   - run id, commit sha, scenario pack id, seed, mode (`fixture|replay|live`), gate results.
3. Define canonical gate result statuses:
   - `pass`, `fail`, `advisory`, `not_applicable`.
4. Define ownership map for each gate and required artifact outputs.

Phase Improvement Contract:

1. Baseline snapshot: no formal gate-evaluation contract.
2. Expected delta: machine-readable readiness contract and run-ledger schema exist.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. Gate contract and run-ledger schema reviewed and merged.
2. All gates have explicit evaluator owners.

### Phase 1: G0 Scenario Contracts and Oracles

Goals:

1. Convert class-1 scenarios into machine-checkable packs.
2. Establish scenario-specific scoring profiles.

Implementation:

1. Create initial class-1 packs:
   - calculator core arithmetic/composition,
   - calculator edge/error handling.
2. Define oracle assertions per pack.
3. Define scoring profiles (calculator correctness-dominant).
4. Add contract tests for scenario-pack validity.

Phase Improvement Contract:

1. Baseline snapshot: scenario quality mostly prose/manual.
2. Expected delta: class-1 packs are machine-validated with explicit oracle contract.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. At least 2 class-1 packs have validated oracle contracts.
2. Scenario-pack schema validation is required in test pipeline.

### Phase 2: G1 Replayability and Fixture Pipeline

Goals:

1. Ensure deterministic replay for class-1 simulation runs.
2. Separate fixture/replay and live modes cleanly.

Implementation:

1. Implement seed-locked runner with deterministic ordering.
2. Add fixture capture/replay store and pinning policy.
3. Add runner checks for deterministic inputs:
   - scenario pack checksum,
   - seed list,
   - model/runtime config.
4. Emit replayability metrics in run ledger.

Phase Improvement Contract:

1. Baseline snapshot: replay determinism not enforced.
2. Expected delta: class-1 reruns with same seed/config produce stable result vectors.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. Replay stability reaches `>= 99%` on pilot window.
2. Fixture/replay mode is default for class-1 gating runs.

### Phase 3: G2 Score Consistency

Goals:

1. Make score computation deterministic and diff-friendly.
2. Detect scorer drift as a first-class failure.

Implementation:

1. Implement deterministic scorer with fixed rounding/aggregation conventions.
2. Persist per-run score vector and component metrics.
3. Add scorer golden tests for representative runs.
4. Add scorer-version field to run ledger.

Phase Improvement Contract:

1. Baseline snapshot: scoring comparability is limited.
2. Expected delta: same seed/config yields identical score vectors (`100%` reproducible).
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. Scorer golden tests are stable.
2. Score reproducibility reaches `100%` in replay mode.

### Phase 4: G3 Trace Integrity (Schema Gate)

Goals:

1. Make trace schema validation a required simulation gate.
2. Fail fast on observability contract drift.

Implementation:

1. Integrate JSONL schema validation (`jq -s` + `ajv`) into simulation runner.
2. Gate class-1 runs on schema pass (`100%` required).
3. Add failure diagnostics that identify first invalid entry and field path.
4. Publish operator commands in docs for local troubleshooting.

Phase Improvement Contract:

1. Baseline snapshot: log schema validation exists but is not gating simulation.
2. Expected delta: every class-1 run enforces schema validity.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. Schema validation failures are surfaced as explicit gate failures.
2. Class-1 run reports include schema validation summary.

### Phase 5: G4 Baseline Diff Engine

Goals:

1. Make every run comparable to pinned baseline evidence.
2. Convert raw run output into actionable deltas.

Implementation:

1. Define baseline snapshot format (scores + key trace counters + gate statuses).
2. Implement diff engine output:
   - improved, regressed, unchanged,
   - suspected causes by gate dimension.
3. Add non-actionable-noise classification and thresholding.
4. Persist diff reports in run artifacts.

Phase Improvement Contract:

1. Baseline snapshot: no guaranteed baseline diff output per run.
2. Expected delta: `100%` class-1 runs produce baseline diff reports.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. Baseline diff report generation coverage reaches `100%`.
2. Noise rate is below `20%` non-actionable threshold.

### Phase 6: G5 CI and Nightly Operationalization

Goals:

1. Enforce class-1 readiness in CI.
2. Add nightly longitudinal readiness evidence.

Implementation:

1. Add CI workflow job:
   - run class-1 fixture simulation matrix,
   - evaluate `G0-G5`,
   - fail PR on gate failure.
2. Add nightly workflow:
   - expanded seed matrix,
   - trend report publication.
3. Add PR summary annotations with gate outcomes and key regressions.
4. Add release checklist item requiring readiness gate pass.

Phase Improvement Contract:

1. Baseline snapshot: simulation is not an enforced merge gate.
2. Expected delta: class-1 readiness gate is enforced in CI and tracked nightly.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. CI gate blocks merges on class-1 readiness failures.
2. Nightly reports are generated and archived.

### Phase 7: Stabilization Window and Advisory Expansion

Goals:

1. Satisfy full class-1 observation window.
2. Add class-2+ packs as advisory only.

Implementation:

1. Run stabilization window (`20` consecutive runs, `5` seeds, `2` sessions, `3` days).
2. Publish readiness decision record:
   - class-1 gate status,
   - unresolved risks,
   - recommended next-scope.
3. Add assistant/debate packs under advisory mode (non-gating).

Phase Improvement Contract:

1. Baseline snapshot: no stabilized class-1 readiness decision record.
2. Expected delta: class-1 readiness claim is evidence-backed and auditable.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. Observation window criteria satisfied and documented.
2. Class-2+ remains advisory until explicit promotion decision.

## CI Integration Tasks

1. Add `simulation-readiness` workflow job for PRs:
   - validate scenario-pack schemas,
   - run class-1 fixture matrix,
   - run schema validation on generated logs,
   - emit baseline diff summary.
2. Add nightly `simulation-readiness-trend` workflow:
   - larger seed/session matrix,
   - trend + noise report artifact.
3. Add standardized run artifact bundle:
   - run ledger JSONL,
   - score vectors,
   - gate results,
   - baseline diff,
   - schema validation output.
4. Add branch protection requirement for class-1 gate once flakiness threshold is met.

## Test Strategy

1. Unit tests:
   - scenario contract parser/validator,
   - scorer determinism,
   - gate evaluator logic.
2. Integration tests:
   - fixture replay stability,
   - schema-gate enforcement,
   - baseline diff generation.
3. Acceptance tests:
   - class-1 calculator end-to-end simulation run with gate report.
4. Regression tests:
   - ensure gate evaluator catches intentionally injected failures.

## Risks and Mitigations

1. Risk: flaky CI from hidden nondeterminism.
   - Mitigation: fixture-first gate mode, deterministic runner inputs, scorer goldens.
2. Risk: baseline drift noise overwhelms signal.
   - Mitigation: stricter oracle contracts, noise classification, scoped class-1 gate.
3. Risk: premature action on early data.
   - Mitigation: enforce observation-window completion before mutation recommendations are actionable.
4. Risk: operational overhead for fixture updates.
   - Mitigation: define fixture lifecycle policy and update cadence with review gates.

## Completion Criteria

1. ADR 0027 gates `G0-G5` are implemented for class-1 packs.
2. Class-1 readiness gate is enforced in CI and tracked nightly.
3. Observation window criteria are met with documented readiness decision.
4. Documentation and operator workflows are published and indexed.
