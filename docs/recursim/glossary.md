# Recursim Glossary

## Core Simulation Terms

- `Scenario Pack`: a versioned contract that defines the scenario, seeds, scripted steps or fixtures, oracle assertions, and scoring weights.
- `Pack Class`: readiness scope tier for a pack.
  - class-1: can become gating after readiness evidence.
  - class-2+: advisory until explicitly promoted.
- `Seed Set`: deterministic input set used to make runs reproducible and comparable.
- `Run Scope`: isolated runtime namespace for one run (state/toolstore/tmp paths).
- `Run Scope ID`: unique identifier bound to a run scope and persisted in run evidence.
- `Oracle`: machine-checkable expectation attached to one step.
- `Oracle Verdict`: pass/fail result for a single oracle check.
- `Score Vector`: weighted metric summary (`correctness`, `contract_adherence`, `repair_efficiency`, `reuse_effectiveness`, `overall`).

## Lanes and Modes

- `Execution Lane`: the behavior channel used to execute a pack.
- `Deterministic Lane`: fixture/replay execution where reproducibility is the first-class objective.
- `Live-Shadow Lane`: runtime execution lane that calls real agents/tools in isolated scope and scores observed outcomes.
- `Fixture Mode`: generate baseline artifacts/evidence for later replay.
- `Replay Mode`: rerun against fixture contracts to test stability and score consistency.
- `Live Mode`: execute live-shadow behavior directly and record lane evidence.
- `Replay Stability`: reproducibility measure for comparable replay runs.

## Gates and Evidence

- `G0`: scenario contract validity.
- `G1`: replayability.
- `G2`: score consistency.
- `G3`: trace schema integrity.
- `G4`: baseline diff completeness.
- `G5`: operationalization context (`local`, `ci`, `nightly`).
- `Run Ledger`: append-only JSONL evidence stream for simulation runs.
- `Baseline Diff`: structured comparison between current run and prior comparable run.
- `Advisory Status`: non-gating signal summary for packs not promoted to release gates.

## Status Vocabulary

- `pass`: gate satisfied.
- `fail`: gate violated.
- `advisory`: measured but non-gating.
- `not_applicable`: intentionally inactive in this mode.
