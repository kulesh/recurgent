# ADR 0027: Simulation Preparedness and Readiness Gates

- Status: proposed
- Date: 2026-02-21

## Context

Recurgent has enough runtime infrastructure to begin automated simulation, but current validation evidence shows a gap between infrastructure maturity and scenario-level semantic stability.

Current state:

1. Reliability and lifecycle infrastructure exists (ADR 0023), role/profile continuity exists (ADR 0024), authority boundaries exist (ADR 0025), and response-content continuity exists (ADR 0026).
2. Phase validation reports show tests are consistently green while example semantics still fluctuate by phase and run conditions.
3. External-data scenarios (news/movies/recipe) are noisy due to upstream variability, while closed-world scenarios (calculator) expose deterministic correctness gaps.

Without a simulation-preparedness contract, Recursim risks producing high-volume but low-quality evidence (flaky signals, unclear causality, weak regression attribution).

This ADR defines a readiness gate layer that must be satisfied before simulation is treated as a primary evolution control loop.

## Decision

Adopt a Simulation Preparedness contract with explicit readiness gates and phased activation policy.

Readiness is measured across six gates:

1. `G0 Contracted Scenarios`: scenario packs have machine-checkable oracles and scoring contracts.
2. `G1 Replayability`: fixed-seed reruns are replay-stable in fixture/replay mode.
3. `G2 Score Consistency`: scoring output is deterministic and diffable across runs.
4. `G3 Trace Integrity`: logs validate against machine-readable schema and required trace-linkage fields.
5. `G4 Baseline Diffs`: each run is compared to a pinned baseline with actionable deltas.
6. `G5 Operationalization`: simulation harness runs in CI/nightly with pass/fail policy.

Gate dependency rule:

1. Gates are sequentially dependent, not independently satisfiable.
2. `G0` must pass before `G2` is considered meaningful.
3. `G1` must pass before `G4` is considered actionable.

Simulation classes are activated incrementally:

1. Class 1 (`self-contained`, calculator-centric) must pass `G0-G5` first.
2. Class 2+ (`inter-connected`, `interactive`, `networked`) remain non-gating until class 1 stability is sustained.

### Readiness Contract Sketch

```yaml
simulation_preparedness:
  version: 1
  gates:
    G0: scenario_contracts
    G1: replayability
    G2: score_consistency
    G3: trace_integrity
    G4: baseline_diffs
    G5: ci_operationalization
  activation_policy:
    class_1: require [G0, G1, G2, G3, G4, G5]
    class_2_plus: advisory_until_class_1_stable
```

### Scenario Contract Sketch

```yaml
id: calculator-core-v1
class: self_contained
oracle:
  type: deterministic
  assertions:
    - add_chain_correct
    - multiply_chain_correct
    - sqrt_expected_precision
scoring:
  profile: calculator_core_v1
  correctness_weight: 0.7
  contract_adherence_weight: 0.15
  repair_efficiency_weight: 0.1
  reuse_weight: 0.05
replay:
  mode: fixture
  seeds: [11, 19, 23, 31, 43, 59, 71, 97]
```

Scoring profile rule:

1. Weight sets are scenario-class specific, not universal defaults.
2. Closed-world calculator packs prioritize correctness dominance.
3. Open-world assistant/debate packs may rebalance toward continuity, provenance, and orchestration coherence.

## Status Quo Baseline

1. Tests are stable, but examples are not uniformly stable:
   - ADR-0024 rollup reports full suite pass across phases with calculator regressions in multiple phases (`docs/reports/adr-0024-phase-validation-rollup.md`).
2. External-data scenarios remain variable:
   - news/movies/recipe flows show capability and source variability across phases/runs (`docs/reports/adr-0023-phase-validation-report.md`, `docs/reports/adr-0024-phase-validation-rollup.md`).
3. Observability is strong but not yet used as a strict simulation gate:
   - trace docs exist (`docs/observability.md`) and log schemas now exist (`specs/contract/v1/recurgent-log-entry.schema.json`, `specs/contract/v1/recurgent-log-stream.schema.json`), but simulator-run gating is not enforced.

## Expected Improvements

1. Replay stability:
   - fixed-seed fixture runs achieve `>= 99%` identical score vectors across repeated executions of the same commit.
2. Regression attribution speed:
   - reduce mean time to identify primary regression source from manual multi-hour trace inspection to `<= 1 CI cycle` via baseline diffs.
3. Signal quality:
   - reduce external-drift-induced false regressions in gating scenarios by `>= 70%` through fixture/replay first policy.
4. Scenario coverage:
   - establish at least 3 machine-scored scenario packs for initial gate:
     1. calculator core arithmetic/composition,
     2. assistant continuity/source-follow-up,
     3. debate role/orchestration coherence.

## Non-Improvement Expectations

1. This ADR does not change runtime semantics by itself (no automatic fixes to calculator/news behavior).
2. This ADR does not authorize autonomous policy mutation (ADR 0025 authority boundary remains intact).
3. This ADR does not replace acceptance tests or runtime contract suites; it adds simulation governance on top.

## Validation Signals

1. Tests:
   - existing Ruby suite remains green (`bundle exec rspec`, `bundle exec rubocop`).
   - simulation harness tests validate scenario loading, scoring determinism, replay controls.
2. Traces/logs:
   - each simulation run emits JSONL logs with `trace_id`, `call_id`, `parent_call_id`, `depth`, `outcome_status`.
   - logs validate against `specs/contract/v1/recurgent-log-stream.schema.json`.
3. Thresholds:
   - `G1`: replay stability `>= 99%`.
   - `G2`: score diff reproducibility `100%` for same seed/config.
   - `G3`: schema validation pass rate `100%` for simulation-generated logs.
   - `G4`: baseline diff report generated for every simulation run.
   - `G5`: CI gate enforces readiness policy on class-1 packs.
4. Observation window:
   - minimum `20` consecutive class-1 runs across at least `5` seeds, `2` sessions, and `3` calendar days before class-1 gate is considered stable.

## Rollback or Adjustment Triggers

1. If replay stability drops below `95%` for class-1 fixture scenarios:
   - freeze promotion of new simulator classes and remediate determinism leaks first.
2. If schema validation failures exceed `0` in simulation-run logs:
   - fail readiness gate and fix observability contract before accepting run results.
3. If baseline diff noise remains high (`> 20%` runs with non-actionable deltas):
   - tighten scenario contracts and scoring definitions before broadening scenario set.

## Scope

In scope:

1. readiness-gate contract for simulation activation,
2. scenario contract/oracle requirements,
3. replay/baseline/diffability requirements,
4. CI/nightly gate criteria for class-1 simulation.

Out of scope:

1. full Recursim implementation details (separate product spec and implementation plan),
2. autonomous recommendation enactment,
3. class-2/3/4 simulation gating.

## Consequences

### Positive

1. Simulation runs become falsifiable engineering evidence instead of anecdotal demos.
2. Regression diagnosis becomes faster and more mechanical.
3. Evolution claims become measurable against explicit readiness thresholds.

### Tradeoffs

1. Adds up-front contract/scoring work before broad simulation rollout.
2. Requires fixture management and baseline maintenance discipline.
3. Slows scope expansion until class-1 gate stability is demonstrated.

## Alternatives Considered

1. Start large-scale simulation immediately without readiness gates.
   - Rejected: high risk of noisy and non-actionable results.
2. Continue manual examples as primary evolution mechanism.
   - Rejected: insufficient coverage and weak repeatability.
3. Limit to calculator-only simulation without shared readiness contract.
   - Rejected: useful for bootstrap, but does not create reusable governance model for other scenario classes.

## Rollout Plan

1. Phase 1: Define simulation contract surface.
   - publish scenario-pack schema/oracle/scoring interfaces,
   - define fixture/replay modes and baseline snapshot format.
2. Phase 2: Implement class-1 harness MVP.
   - calculator-first packs + deterministic scorer + run ledger.
3. Phase 3: Wire readiness gates.
   - implement `G0-G5` checks, schema validation, baseline-diff reporting.
4. Phase 4: Operationalize.
   - add CI/nightly runs for class-1 packs,
   - publish run health dashboard/reporting.
5. Phase 5: Expand cautiously.
   - add assistant/debate packs under advisory mode, promote to gating only after meeting gate thresholds.

## Guardrails

1. Do not treat live-network variability as primary gating evidence; fixture/replay evidence is authoritative for readiness decisions.
2. Keep scenario scoring contracts explicit and machine-checkable; avoid prose-only pass/fail criteria.
3. Keep simulation pressure separate from runtime mutation authority (observe/propose/enact boundaries remain explicit).
4. Avoid overfitting to one scenario: require multi-pack evidence before claiming class-level readiness.
5. Do not use simulation outputs to justify runtime/policy mutations until the observation window is satisfied.

## Ubiquitous Language Additions

Add these terms to [`docs/ubiquitous-language.md`](../ubiquitous-language.md):

1. `Simulation Preparedness`
2. `Readiness Gate`
3. `Scenario Pack`
4. `Oracle Contract`
5. `Replay Stability`
6. `Baseline Diff`
