# Simulation Readiness Operations

This document explains how to run and interpret local simulation readiness checks for `G0`-`G5`.
For conceptual orientation, start with [`docs/recursim/README.md`](recursim/README.md).

## Gate Semantics (`G0`-`G5`)

### `G0` Scenario Contract Validity

Purpose:
- Confirms the scenario pack contract/oracle is valid and loadable by the runner.

Expected behavior:
- `pass` when the run executes with a valid scenario pack.
- Invalid pack/schema problems usually fail earlier (runner/spec validation), not as a normal in-band gate transition.

### `G1` Replayability

Purpose:
- Measures deterministic replay stability for the same pack/config/seeds.

Expected behavior:
- `pass` in `replay` mode when stability is `>= 0.99`.
- `fail` in `replay` mode when stability is `< 0.99`.
- `advisory` in non-replay modes (`fixture`/`live`).

### `G2` Score Consistency

Purpose:
- Detects score-vector drift against prior comparable replay evidence.

Expected behavior:
- `pass` when score vector matches a prior replay run for same pack/seeds/scorer.
- `fail` when comparable replay exists and score vector drifts.
- `advisory` on the first replay (no comparable replay baseline yet).
- `advisory` in non-replay modes.

### `G3` Trace Schema Integrity

Purpose:
- Validates JSONL trace entries against the log schema.

Expected behavior:
- `pass` when `--trace-log` is provided and all entries validate.
- `fail` when any entry is invalid (message includes first invalid field path/index/reason).
- `advisory` when no trace log is provided.

### `G4` Baseline Diff Completeness

Purpose:
- Ensures each run emits a baseline diff classification and comparison metadata.

Expected behavior:
- `pass` when a classification is present (`no_baseline`, `improved`, `regressed`, `unchanged`).
- `fail` only when classification is missing.

### `G5` Operationalization Context

Purpose:
- Signals whether run context matches CI/nightly operational contracts.

Expected behavior:
- `pass` in `ci` mode.
- `pass` in `nightly` mode when `--nightly-trend-report` is provided.
- `fail` in `nightly` mode when trend report path is missing.
- `not_applicable` in `local` mode.

## Status Meanings

- `pass`: readiness condition satisfied for the current gate.
- `fail`: readiness condition violated; investigate before claiming stability.
- `advisory`: measured but non-blocking in this run mode/phase.
- `not_applicable`: gate intentionally not enforced in this context.

## Run Class-1 Pack

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml \
  --mode fixture \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl > ../../tmp/simulation/core-fixture.json
```

Before this run:
- `../../tmp/simulation/fixtures` and `../../tmp/simulation/run-ledger.jsonl` may not exist yet.

After this run:
- Fixture snapshots are created/updated under fixture root.
- Ledger appends one record.
- Typical gate snapshot for local fixture run:
  - `G0=pass`, `G1=advisory`, `G2=advisory`, `G3=advisory` (unless trace provided), `G4=pass`, `G5=not_applicable`.

Inspect gate statuses:

```bash
jq '{g0:.gates.G0.status,g1:.gates.G1.status,g2:.gates.G2.status,g3:.gates.G3.status,g4:.gates.G4.status,g5:.gates.G5.status,score:.score_vector,baseline:.metrics.baseline_diff_report.classification}' \
  ../../tmp/simulation/core-fixture.json
```

## Replay Determinism Check (`G1`, `G2`)

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml \
  --mode replay \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl > ../../tmp/simulation/core-replay-1.json

mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml \
  --mode replay \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl > ../../tmp/simulation/core-replay-2.json
```

Before first replay:
- A fixture run should already exist for the same pack/seeds.

After first replay:
- `G1` is usually `pass` if replay is stable.
- `G2` is usually `advisory` (`no prior comparable replay`).

After second replay (same config):
- `G2` should become `pass` if score vector is reproducible.
- `G2=fail` indicates score drift.

Inspect both:

```bash
jq '{g1:.gates.G1.status,g2:.gates.G2.status,g2_msg:.gates.G2.message,score:.score_vector.overall,baseline:.metrics.baseline_diff_report.classification}' ../../tmp/simulation/core-replay-1.json
jq '{g1:.gates.G1.status,g2:.gates.G2.status,g2_msg:.gates.G2.message,score:.score_vector.overall,baseline:.metrics.baseline_diff_report.classification}' ../../tmp/simulation/core-replay-2.json
```

## Live-Shadow Lane (Advisory)

Live-shadow runs execute real scripted Agent calls in a run-scoped isolated runtime and score oracle verdicts from those outcomes.

Lane replay semantics:
- deterministic lane replay compares payload identity.
- live-shadow lane replay compares oracle verdict reproducibility (`oracle id -> passed`), not raw text/payload identity.

Run calculator live-shadow pack:

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-live-shadow-v1.yaml \
  --mode fixture \
  --fixture-root ../../tmp/simulation/fixtures \
  --live-shadow-root ../../tmp/simulation/live-shadow \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl > ../../tmp/simulation/calculator-live-shadow-fixture.json
```

Replay calculator live-shadow pack:

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-live-shadow-v1.yaml \
  --mode replay \
  --fixture-root ../../tmp/simulation/fixtures \
  --live-shadow-root ../../tmp/simulation/live-shadow \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl > ../../tmp/simulation/calculator-live-shadow-replay.json
```

Inspect live-shadow run output:

```bash
jq '{lane:.execution_lane,run_scope_id:.run_scope_id,g1:.gates.G1.status,g2:.gates.G2.status,usage:.usage_telemetry,steps:(.metrics.per_seed_results[0].step_results|length)}' ../../tmp/simulation/calculator-live-shadow-replay.json
```

## Trace Schema Validation (`G3`)

Use a trace log path:

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml \
  --mode replay \
  --trace-log "$XDG_STATE_HOME/recurgent/recurgent.jsonl" \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl > ../../tmp/simulation/core-replay-trace.json
```

Before this run:
- Ensure trace file exists and is valid JSONL, or intentionally provide known-good logs.

After this run:
- `G3=pass` if schema-valid.
- `G3=fail` if invalid (diagnostic includes first failing field path/index).

Diagnose first invalid trace entry:

```bash
jq -r '.gates.G3.message' ../../tmp/simulation/core-replay-trace.json
```

### Optional Ajv Cross-Check

If `ajv` is installed:

```bash
jq -s . "$XDG_STATE_HOME/recurgent/recurgent.jsonl" > /tmp/recurgent-log-stream.json
ajv validate \
  -s specs/contract/v1/recurgent-log-stream.schema.json \
  -r specs/contract/v1/recurgent-log-entry.schema.json \
  -d /tmp/recurgent-log-stream.json
```

## Baseline Diff Validation (`G4`)

`G4` verifies diff metadata is always emitted.

Inspect classification from any run JSON:

```bash
jq -r '.metrics.baseline_diff_report.classification' ../../tmp/simulation/core-replay-2.json
```

Expected values:
- `no_baseline` on first comparable run for a mode/config.
- `improved`, `regressed`, or `unchanged` once a baseline exists.

## CI and Nightly Operationalization (`G5`)

`G5` depends on operational mode:
- `local`: `not_applicable`
- `ci`: `pass`
- `nightly`: `pass` only when `--nightly-trend-report` is provided

Local CI emulation:

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml \
  --mode replay \
  --operational-mode ci \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl > ../../tmp/simulation/core-replay-ci.json
```

Nightly-mode emulation:

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml \
  --mode replay \
  --operational-mode nightly \
  --nightly-trend-report ../../tmp/simulation/nightly/nightly-trend-report.json \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/nightly/run-ledger.jsonl > ../../tmp/simulation/core-replay-nightly.json
```

## Phase-7 Window Runs (Stabilization Evidence)

Run one class-1 window session:

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim-window-run \
  --out-root ../../tmp/simulation/phase-7 \
  --session-id local-phase7-r1
```

Before a window run:
- You may have zero prior records.

After each window run:
- A run bundle appears under `../../tmp/simulation/phase-7/runs/<timestamp>-<session_id>/`.
- `summary.json` includes `qualifying: true|false`.
- Ledger appends replay evidence for both required class-1 packs.

Evaluate window status:

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim-window-status \
  --ledger-path ../../tmp/simulation/phase-7/run-ledger.jsonl \
  --write-json ../../tmp/simulation/phase-7/window-status.json \
  --write-decision-record ../../tmp/simulation/phase-7/readiness-decision.md
```

Status output tells you whether observation-window requirements are met:
- required consecutive qualifying runs,
- distinct seeds,
- qualifying sessions,
- distinct UTC days,
- reset events.

## Phase-7b Advisory Status Report

Generate advisory rollup for class-2+ packs:

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim-advisory-report \
  --ledger-path ../../tmp/simulation/nightly/run-ledger.jsonl \
  --pack-ids assistant-continuity-v1,debate-orchestration-v1 \
  --write-json ../../tmp/simulation/nightly/advisory-status.json \
  --write-markdown ../../tmp/simulation/nightly/advisory-status.md
```

Before this run:
- Ledger must already contain class-2+ replay entries for the requested pack IDs.

After this run:
- JSON and markdown advisory summaries are written.
- You get per-pack run counts, trend deltas, latest gate snapshots, and top failure signatures.

## GitHub Workflows

- CI readiness gate: [`.github/workflows/simulation-readiness-ci.yml`](../.github/workflows/simulation-readiness-ci.yml)
- Nightly trend pipeline: [`.github/workflows/simulation-readiness-nightly.yml`](../.github/workflows/simulation-readiness-nightly.yml)
