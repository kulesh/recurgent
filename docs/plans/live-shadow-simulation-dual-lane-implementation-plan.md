# Live-Shadow Simulation Dual-Lane Implementation Plan

- Status: draft
- Date: 2026-02-22
- Scope: [ADR 0028](../adrs/0028-live-shadow-simulation-and-dual-lane-evidence.md) live-shadow simulation lane on top of [ADR 0027](../adrs/0027-simulation-preparedness-and-readiness-gates.md) deterministic readiness lane

## Objective

Operationalize [ADR 0028](../adrs/0028-live-shadow-simulation-and-dual-lane-evidence.md) so Recurgent can measure runtime semantic behavior (live-shadow) without degrading deterministic readiness reliability.

Primary outcomes:

1. Add a live-shadow simulation lane that executes scripted real agent calls in run-scoped isolation.
2. Preserve deterministic lane as primary class-1 gating signal.
3. Capture lane-aware evidence (scores, gates, isolation health, usage telemetry) in one ledger/reporting surface.

## Status Quo Baseline

1. Simulation runner is deterministic-oracle only ([`runtimes/ruby/lib/recurgent/simulation_runner.rb`](../../runtimes/ruby/lib/recurgent/simulation_runner.rb)) and does not execute live runtime flows.
2. Phase-7 evidence confirms deterministic infrastructure maturity but ongoing semantic instability in live examples ([`docs/baselines/2026-02-22/adr-0027/phase-7b-validation-report.md`](../baselines/2026-02-22/adr-0027/phase-7b-validation-report.md)).
3. Run ledger currently captures gate/score evidence, but not live-shadow lane metadata and token/cost telemetry for runtime-executed calls.

## Expected Improvements

1. Live semantic signal coverage:
   - from manual ad hoc example analysis to machine-scored live-shadow packs for calculator and assistant.
2. Isolation confidence:
   - run-scope contamination checks reach `100%` pass across seed/session matrix.
3. Evidence completeness:
   - lane metadata and usage telemetry fields present on `100%` live-shadow ledger entries (with explicit `unknown` values when provider does not return data).
4. Regression attribution:
   - lane-split reports identify deterministic-only vs live-shadow-only vs cross-lane regressions in one artifact.

## Non-Improvement Expectations

1. This plan does not auto-repair failing runtime semantics.
2. This plan does not promote live-shadow to gating before explicit promotion decision criteria are met.
3. This plan does not relax [ADR 0025](../adrs/0025-awareness-substrate-and-authority-boundary.md) authority boundaries (`observe/propose/enact` separation remains unchanged).

## Validation Signals and Thresholds

1. Tests/specs:
   - full Ruby suite remains green,
   - new unit/integration specs for lane selection, isolation, script execution, live oracles, and telemetry mapping.
2. Traces/logs:
   - live-shadow step records include trace linkages (`trace_id`, `call_id`, `depth`, `outcome_status`),
   - ledger includes lane metadata and usage telemetry.
3. Thresholds:
   - deterministic lane class-1 gate behavior remains unchanged,
   - isolation contamination checks `100%` pass,
   - live-shadow step execution coverage `100%` for scripted steps,
   - oracle evaluation coverage `100%` for pack oracles,
   - live-shadow replay comparability is oracle-verdict-based (not raw payload-string identity),
   - telemetry field presence `100%` for live-shadow ledger entries.
4. Observation window:
   - live-shadow remains advisory for at least `20` runs across `>= 5` seeds and `>= 3` UTC days before promotion decision.

## Rollback or Adjustment Triggers

1. Any deterministic-lane class-1 gate regression introduced by live-shadow changes -> pause live-shadow rollout and restore deterministic baseline first.
2. Any cross-run contamination in state/tool/artifact namespaces -> block further live-shadow phases until isolation defect is fixed.
3. Missing live-shadow usage telemetry fields in ledger -> block promotion decisions until telemetry coverage is restored.
4. Advisory noise above `20%` ambiguous regressions -> tighten live-shadow scenario/oracle contracts before adding new packs.

## Non-Goals

1. Replacing deterministic simulation lane.
2. Enabling autonomous runtime mutations from simulation output.
3. Broad open-world/networked scenario gating in first live-shadow iteration.

## Design Constraints

1. Isolation-first sequencing: implement and prove run-scoped isolation before executor implementation.
2. Run-scoped isolation must include state, tool registry, artifact store, pattern memory, role profile registry, and proposals.
3. Durable writes outside run scope are blocked by default unless scenario pack explicitly opts in.
4. Lane semantics are explicit in contracts and ledger; no hidden lane inference.
5. Deterministic lane remains the control baseline throughout rollout.
6. Schema changes must be versioned and validated before CI/nightly adoption.
7. Replay comparison semantics are lane-specific:
   - deterministic lane: payload identity,
   - live-shadow lane: oracle verdict reproducibility with tolerance-aware numeric checks.

## Delivery Strategy

### Phase 0: Contract and Schema Extension

Goals:

1. Extend simulation scenario-pack contract for lane and script metadata.
2. Extend run-ledger schema for lane + usage telemetry.

Implementation:

1. Update scenario-pack schema ([`specs/contract/v1/simulation-scenario-pack.schema.json`](../../specs/contract/v1/simulation-scenario-pack.schema.json)):
   - `execution.lane` (`deterministic` | `live_shadow`),
   - `execution.isolation` (`run_scoped`),
   - `scenario.role`, `scenario.script[]` fields for live-shadow.
2. Update run-ledger schema ([`specs/contract/v1/simulation-run-ledger.schema.json`](../../specs/contract/v1/simulation-run-ledger.schema.json)):
   - `execution_lane`,
   - `run_scope_id`,
   - `usage_telemetry` object (`provider`, `model`, `input_tokens`, `output_tokens`, `total_tokens`, `estimated_cost_usd`, `availability`).
3. Update `Agent::SimulationPackContract` for new validation rules.

Phase Improvement Contract:

1. Baseline snapshot: no lane metadata in pack/ledger contracts.
2. Expected delta: lane + telemetry contract surfaces are machine-validated.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. Schema and contract tests cover new fields and reject invalid payloads.
2. Existing deterministic packs validate under updated contract.

### Phase 1: Isolation Proof Harness (Before Executor)

Goals:

1. Introduce run-scoped namespace builder for live-shadow runs.
2. Prove no cross-run leakage across all runtime stores.

Implementation:

1. Add `SimulationRunScope` utility that creates per-run roots (e.g. `tmp/simulation/live-shadow/<run_scope_id>/<seed>/...`).
2. Inject run-scoped paths for runtime stores used during live-shadow execution.
3. Add isolation specs:
   - run A forges tool/artifact/state entries,
   - run B starts clean with same seed/config,
   - assert no inherited state/tool/artifact/proposal/profile contamination.
4. Add teardown policy and crash-safe cleanup strategy.

Phase Improvement Contract:

1. Baseline snapshot: no formal isolation harness for simulation runs.
2. Expected delta: isolation contamination checks pass deterministically.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. Isolation test matrix passes `100%`.
2. Leak detector assertions fail fast with explicit diagnostics.

### Phase 2: Live-Shadow Script Executor Core

Goals:

1. Execute scripted role calls through real runtime path.
2. Capture step-level outcomes and trace references.

Implementation:

1. Add lane selector in `SimulationRunner`:
   - deterministic path (existing),
   - live-shadow path (new).
2. Implement live-shadow step runner:
   - instantiate role (`Agent.for(role)`),
   - execute ordered `scenario.script` calls,
   - capture `{ step_id/call, args, kwargs, outcome_summary, trace_ref }`.
3. Store per-seed live execution payload in fixture/replay format compatible with scorer.
4. Add replay comparator semantics for live-shadow:
   - compare oracle verdict stability by oracle id,
   - compare numeric expectations via declared tolerances,
   - do not require raw generated payload or prose identity.

Phase Improvement Contract:

1. Baseline snapshot: no live runtime execution in simulation.
2. Expected delta: scripted call sequences execute and emit structured step outcomes with lane-correct replay comparator behavior.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. Live-shadow pack executes end-to-end for at least one calculator script.
2. Per-seed payloads are persisted and replay-comparable using oracle-verdict reproducibility.

### Phase 3: Live Oracle Surface

Goals:

1. Add oracle kinds that evaluate live step outcomes/log conditions.
2. Keep deterministic and live oracle evaluation under one interface.

Implementation:

1. Extend oracle evaluator with live kinds:
   - `live_outcome_value`,
   - `live_outcome_error`,
   - `live_provenance_envelope`,
   - `live_continuity_ref_resolution`.
2. Support step addressing (`step`, `step_index`, optional aliases).
3. Emit failure details with explicit failure typing (`semantic_regression`, `contract_mismatch`, `trace_integrity_failure`).

Phase Improvement Contract:

1. Baseline snapshot: evaluator handles deterministic-only kinds.
2. Expected delta: live outcomes are machine-checkable via oracle contracts.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. Oracle evaluator specs cover deterministic + live kinds.
2. Error diagnostics identify failing step, expectation, and observed value.

### Phase 4: Shared Scoring/Gates/Ledger Integration

Goals:

1. Integrate live-shadow output into shared scoring and gate pipeline.
2. Persist lane-aware usage telemetry in ledger.

Implementation:

1. Extend `SimulationRunner` ledger payload with:
   - `execution_lane`,
   - `run_scope_id`,
   - `usage_telemetry`.
2. Collect usage telemetry from provider responses where available; populate explicit `unknown` markers where unavailable.
3. Preserve [ADR 0027](../adrs/0027-simulation-preparedness-and-readiness-gates.md) gate semantics; apply live-shadow in advisory mode by policy.
4. Ensure baseline diff and trend reports include lane dimension.

Phase Improvement Contract:

1. Baseline snapshot: ledger is lane-agnostic and telemetry-light.
2. Expected delta: lane-aware and telemetry-aware evidence is complete and queryable.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. `100%` live-shadow ledger entries include required telemetry keys.
2. Deterministic lane outputs remain schema-compatible and unchanged in behavior.

### Phase 5: Initial Live-Shadow Packs

Goals:

1. Introduce first operational live-shadow packs.
2. Keep scope narrow and high-signal.

Implementation:

1. Add `calculator-live-shadow-v1` pack:
   - scripted arithmetic/continuity calls,
   - deterministic value assertions.
2. Add `assistant-live-shadow-v1` advisory pack:
   - continuity follow-up behavior,
   - boundary/provenance/error-shape assertions.
3. Version and checksum packs under existing scenario-pack structure.

Phase Improvement Contract:

1. Baseline snapshot: no live-shadow packs.
2. Expected delta: calculator + assistant live-shadow evidence produced consistently.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. Both packs run in local advisory mode.
2. Pack docs describe scripted steps and oracle intent.

### Phase 6: Reporting, Operator Tooling, and Docs

Goals:

1. Make dual-lane evidence understandable and operable.
2. Provide lane-specific diagnostics and trend views.

Implementation:

1. Extend advisory report tooling for lane-split summaries.
2. Add operator commands for live-shadow runs and lane-comparison outputs.
3. Update documentation:
   - [`docs/simulation-readiness.md`](../simulation-readiness.md) live-shadow runbook,
   - docs indexes/plan maps,
   - UL additions from [ADR 0028](../adrs/0028-live-shadow-simulation-and-dual-lane-evidence.md).

Phase Improvement Contract:

1. Baseline snapshot: reports emphasize deterministic lane only.
2. Expected delta: operators can distinguish deterministic vs live-shadow regressions quickly.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. Lane-split report artifact generated from ledger.
2. Runbook includes before/after expectations for live-shadow commands.

### Phase 7: CI/Nightly Advisory Operationalization

Goals:

1. Run live-shadow automatically in advisory mode.
2. Keep deterministic gating unchanged.

Implementation:

1. Keep existing class-1 deterministic CI gate as required merge signal.
2. Add live-shadow jobs as advisory artifacts (PR summary + nightly archives).
3. Add budget controls (seed count, pack selection) to keep runtime/cost bounded.

Phase Improvement Contract:

1. Baseline snapshot: no automated live-shadow advisory runs.
2. Expected delta: continuous advisory evidence without gate instability.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. CI remains stable with deterministic gating unchanged.
2. Nightly publishes lane-split deterministic + live-shadow artifacts.

### Phase 8: Advisory Observation Window and Promotion Decision Record

Goals:

1. Complete minimum live-shadow advisory observation window.
2. Produce explicit promotion/no-promotion decision artifact.

Implementation:

1. Run advisory window (`>= 20` runs, `>= 5` seeds, `>= 3` days).
2. Publish decision record documenting:
   - stability,
   - unresolved risks,
   - promotion recommendation.
3. Keep promotion manual and explicit.

Phase Improvement Contract:

1. Baseline snapshot: no formal live-shadow promotion decision evidence.
2. Expected delta: promotion decision is evidence-backed and auditable.
3. Observed delta: to be filled after phase validation.

Exit criteria:

1. Decision record published under [`docs/reports/`](../reports).
2. Maintainer decision references explicit thresholds and artifacts.

## Phase Validation Protocol (After Every Phase)

Execute and archive these validations after each phase implementation:

1. Entire Ruby test suite (`bundle exec rspec`).
2. Calculator example run ([`runtimes/ruby/examples/calculator.rb`](../../runtimes/ruby/examples/calculator.rb)) with outcome correctness notes.
3. Personal assistant run with required prompts:
   - top news (Google News, Yahoo! News, NYT),
   - action-adventure movies in theaters,
   - recipe for Jaffna Kool.
4. Log/trace diagnosis for calculator + assistant runs:
   - what happened,
   - expected vs observed,
   - what improved vs did not improve.
5. Persist phase report and raw artifacts under dated baseline paths.

## Test Strategy

1. Unit tests:
   - pack/schema contract validation,
   - isolation scope utilities,
   - live oracle evaluators,
   - telemetry extraction/mapping.
2. Integration tests:
   - live-shadow script execution through runtime,
   - replay comparison across seeds,
   - lane-aware ledger append and report generation.
3. Acceptance tests:
   - calculator live-shadow pack outcomes,
   - assistant live-shadow advisory behavior.
4. Regression tests:
   - deterministic lane unchanged behavior,
   - no cross-run contamination,
   - no schema regressions in logs/ledger.

## Risks and Mitigations

1. Isolation leakage risk -> enforce Phase-1 isolation proofs before executor code.
2. Deterministic lane regression risk -> keep deterministic lane as control and add blocking regression checks.
3. Advisory noise risk -> tighten live pack scripts/oracles before expanding scope.
4. Cost/runtime expansion risk -> emit telemetry + apply seed/pack budget caps in CI/nightly.

## Completion Criteria

1. [ADR 0028](../adrs/0028-live-shadow-simulation-and-dual-lane-evidence.md) phases 0-8 complete with phase-by-phase validation artifacts.
2. Dual-lane evidence is produced in a shared ledger with complete lane + telemetry fields.
3. Deterministic class-1 gating remains healthy and unchanged.
4. Live-shadow advisory promotion decision is documented and auditable.
