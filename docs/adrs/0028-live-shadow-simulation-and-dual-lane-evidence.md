# ADR 0028: Live-Shadow Simulation and Dual-Lane Evidence

- Status: proposed
- Date: 2026-02-22

## Context

[ADR 0027](0027-simulation-preparedness-and-readiness-gates.md) established simulation preparedness gates (`G0`-`G5`) and a deterministic replay harness. That harness is now useful for measuring pipeline reliability, but it does not execute live runtime behavior.

Current mismatch:

1. Deterministic class-1 packs can pass readiness gates while live examples still regress semantically.
2. The deterministic oracle lane validates scoring/replay/ledger mechanics, not runtime solving behavior (`method_missing -> forge/delegate/tool -> guardrails -> outcome`).
3. We currently lack a controlled way to run real agent flows at simulation scale with reproducible evidence semantics.

Recent evidence:

1. [`docs/baselines/2026-02-22/adr-0027/phase-7b-validation-report.md`](../baselines/2026-02-22/adr-0027/phase-7b-validation-report.md) shows deterministic advisory infrastructure is complete.
2. The same report shows live example instability (`solve/history` continuity failures, assistant top-news failure) despite green deterministic infrastructure checks.

The project now needs a second simulation lane: one that runs live runtime behavior in shadow mode without weakening [ADR 0027](0027-simulation-preparedness-and-readiness-gates.md) discipline.

## Decision

Adopt a **dual-lane simulation model**:

1. **Deterministic Lane** (existing): machine-checkable deterministic oracle execution for replay and readiness mechanics.
2. **Live-Shadow Lane** (new): scripted real agent execution with oracle assertions over observed outcomes/logs.

### Design Rule

- Deterministic lane validates **measurement reliability**.
- Live-shadow lane validates **runtime semantic behavior**.
- Neither lane replaces the other.

Replay comparability rule:

1. Deterministic lane compares **payload identity** across replay runs.
2. Live-shadow lane compares **oracle verdict reproducibility** across replay runs (pass/fail and numeric tolerance outcomes), not raw response text identity.
3. Lane-specific replay semantics are explicit contract behavior, not inferred at runtime.

### Live-Shadow Contract Additions

Introduce scenario-pack execution lane metadata:

```yaml
version: 1
id: calculator-live-shadow-v1
class: class_1
execution:
  lane: live_shadow
  isolation: run_scoped
replay:
  mode: replay
  seeds: [11, 19, 23, 31, 43]
scenario:
  role: calculator
  script:
    - call: memory=
      args: [5]
    - call: add
      args: [3]
    - call: multiply
      args: [4]
    - call: sqrt
      args: [144]
oracles:
  - id: sqrt_returns_12
    kind: live_outcome_value
    input:
      step: sqrt
    expect:
      equals: 12.0
      tolerance: 0.000001
```

### Live-Shadow Runtime Mechanics

Per seed/session, the live-shadow runner executes:

1. Build isolated run scope (state/tool/artifact namespace unique to run).
2. Materialize top-level role via runtime API (`Agent.for(...)`).
3. Execute scripted call sequence.
4. Capture step outcomes + trace references.
5. Evaluate live oracles against captured outcomes and required logs.
6. Emit per-seed result payload into existing scorer/gates/ledger pipeline.

Isolation default:

1. Durable tool/artifact writes are blocked outside run scope unless pack contract explicitly opts in.
2. Cross-run namespace contamination is treated as a harness defect, not a scenario failure.

### Gate Policy

Keep [ADR 0027](0027-simulation-preparedness-and-readiness-gates.md) gate model unchanged; apply status interpretation by lane:

1. Deterministic class-1 packs remain primary gating evidence.
2. Live-shadow packs are advisory until deterministic class-1 window is stable.
3. Promotion rule for live-shadow gating requires explicit decision record (maintainer override is explicit, never implicit).

### Current vs Future Execution Shape

Current deterministic path:

```text
scenario pack YAML -> deterministic oracle evaluator -> scorer -> G0..G5 -> ledger
```

Post-ADR dual-lane path:

```text
scenario pack YAML
  -> lane selector
     -> deterministic evaluator (lane A)
     -> live-shadow executor + oracle evaluator (lane B)
  -> shared scorer -> G0..G5 -> ledger
```

## Status Quo Baseline

1. Deterministic simulation readiness infrastructure is implemented and CI-capable ([`docs/simulation-readiness.md`](../simulation-readiness.md), `.github/workflows/simulation-readiness-ci.yml`).
2. Class-1 stabilization evidence can be computed, but day-window criterion still governs readiness ([`docs/reports/simulation-readiness-decision-2026-02-22.md`](../reports/simulation-readiness-decision-2026-02-22.md)).
3. Live runtime semantic failures still appear in manual validation traces ([`docs/baselines/2026-02-22/adr-0027/phase-7b-validation-report.md`](../baselines/2026-02-22/adr-0027/phase-7b-validation-report.md)).

## Expected Improvements

1. Semantic signal availability:
   - from ad hoc manual trace review to machine-scored live-shadow evidence for calculator and assistant packs.
2. Regression attribution quality:
   - classify regressions as deterministic-lane, live-runtime-lane, or both in a single report.
3. Runtime confidence:
   - detect live semantic regressions within one simulation cycle, without waiting for manual example sweeps.
4. Operator ergonomics:
   - unify deterministic and live-shadow evidence in one ledger/report surface.

## Non-Improvement Expectations

1. This ADR does not auto-repair runtime semantics.
2. This ADR does not relax [ADR 0025](0025-awareness-substrate-and-authority-boundary.md) authority boundaries.
3. This ADR does not make networked/open-world scenarios deterministic.

## Validation Signals

1. Tests:
   - simulation runner specs include lane selection, isolation, script execution, and live-oracle evaluation.
   - existing test/lint suite remains green.
2. Traces/logs:
   - each live-shadow step emits trace linkages (`trace_id`, `call_id`, `depth`, `outcome_status`).
   - run ledger stores lane metadata and per-step outcome summary.
   - run ledger stores usage telemetry for live-shadow runs (at minimum: model/provider, input/output token counts when available, and cost estimate if available).
3. Thresholds:
   - lane metadata present on `100%` of simulation ledger entries.
   - live-shadow script execution coverage `100%` for pack-defined steps.
   - oracle evaluation coverage `100%` for pack-defined live oracles.
   - isolation contamination checks pass `100%` (no state/tool/artifact leakage across run scopes for same pack/seed matrix).
   - usage telemetry presence `100%` on live-shadow ledger entries (allowing explicit `unknown` value when provider does not return a field).
4. Observation window:
   - live-shadow remains advisory for at least `20` runs across `>= 5` seeds and `>= 3` days before promotion decision.

## Rollback or Adjustment Triggers

1. If live-shadow isolation leaks state across runs:
   - freeze live-shadow expansion; remediate isolation before adding packs.
2. If live-shadow replay noise makes reports non-actionable (`> 20%` ambiguous regressions):
   - tighten pack contracts and oracle definitions before adding new domains.
3. If deterministic lane stability degrades during live-shadow rollout:
   - pause live-shadow rollout and restore deterministic lane health first.
4. If usage telemetry is missing for live-shadow runs:
   - treat lane readiness evidence as incomplete and block promotion decisions until telemetry is restored.

## Scope

In scope:

1. scenario-pack lane metadata (`deterministic` vs `live_shadow`),
2. live-shadow scripted execution harness,
3. live-oracle kinds for outcome/log checks,
4. shared scorer/gate/ledger integration,
5. advisory-first activation policy for live-shadow packs.
6. live-shadow usage telemetry in run ledger.

Out of scope:

1. autonomous runtime mutation from simulation results,
2. replacing deterministic lane,
3. immediate class-2+ promotion to gating.

## Consequences

### Positive

1. Separates measurement reliability from runtime semantic correctness while preserving one evidence model.
2. Reduces dependence on manual calculator/assistant trace sweeps for regression detection.
3. Keeps [ADR 0027](0027-simulation-preparedness-and-readiness-gates.md) governance discipline intact during expansion.

### Tradeoffs

1. Adds harness complexity (script executor, lane selection, isolation mechanics).
2. Increases simulation run cost and execution time.
3. Requires stricter pack/oracle authoring for live flows.

## Alternatives Considered

1. Keep deterministic-only simulation and continue manual live validations.
   - Rejected: leaves semantic regressions under-instrumented.
2. Replace deterministic lane entirely with live runs.
   - Rejected: loses reproducibility and gate reliability baseline.
3. Run live-shadow as gating immediately.
   - Rejected: premature; requires advisory evidence maturation first.

## Rollout Plan

1. Phase 0: Contract extension.
   - add `execution.lane` and live-script schema fields to pack contract.
2. Phase 1: Isolation proof first.
   - add isolation tests that verify clean per-run state/tool/artifact namespaces and no cross-run leakage.
3. Phase 2: Live-shadow executor core.
   - isolated run scope, scripted call runner, step outcome capture.
4. Phase 3: Live oracle surface.
   - add oracle kinds for outcome value/error/provenance/continuity checks.
5. Phase 4: Shared pipeline integration.
   - feed live-shadow outputs into scorer/gates/ledger with lane metadata and usage telemetry.
6. Phase 5: Initial packs.
   - `calculator-live-shadow-v1` and `assistant-live-shadow-v1` in advisory mode.
7. Phase 6: Reporting and promotion criteria.
   - lane-split trend report + explicit promotion decision record template.

## Guardrails

1. Do not allow live-shadow lane to write durable runtime artifacts outside run-scoped isolation unless pack explicitly opts in.
2. Keep live-shadow non-gating until deterministic class-1 stability is maintained.
3. Treat network-dependent assertions as advisory unless fixture-backed.
4. Keep failure typing explicit (`semantic_regression`, `contract_mismatch`, `trace_integrity_failure`) in reporting.
5. Maintain separate awareness from authority (simulation can observe/propose, not enact).
6. Do not promote live-shadow to gating when usage telemetry or isolation evidence is incomplete.

## Ubiquitous Language Additions

Add these terms to [`docs/ubiquitous-language.md`](../ubiquitous-language.md):

1. `Dual-Lane Simulation`
2. `Deterministic Lane`
3. `Live-Shadow Lane`
4. `Lane Promotion Decision`
5. `Run-Scoped Isolation`
6. `Semantic Regression Signal`
7. `Run Cost Telemetry`
