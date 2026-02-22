# Simulation Readiness Operations

This document defines local operator commands for `G0`-`G5` simulation readiness checks.

## Run Class-1 Pack

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml \
  --mode fixture \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl
```

## Replay Determinism Check (G1)

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml \
  --mode replay \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl
```

Inspect gate statuses:

```bash
jq '{g0:.gates.G0.status,g1:.gates.G1.status,g2:.gates.G2.status,g3:.gates.G3.status,g4:.gates.G4.status,g5:.gates.G5.status,score:.score_vector}' \
  ../../tmp/simulation/replay-run.json
```

## Trace Schema Validation (G3)

Use the runner with a JSONL trace path:

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml \
  --mode replay \
  --trace-log "$XDG_STATE_HOME/recurgent/recurgent.jsonl" \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl
```

### Optional Ajv cross-check

If `ajv` is installed, validate JSONL logs using the contract schema:

```bash
jq -s . "$XDG_STATE_HOME/recurgent/recurgent.jsonl" > /tmp/recurgent-log-stream.json
ajv validate \
  -s specs/contract/v1/recurgent-log-stream.schema.json \
  -r specs/contract/v1/recurgent-log-entry.schema.json \
  -d /tmp/recurgent-log-stream.json
```

## Diagnose First Invalid Trace Entry

```bash
jq -r '.gates.G3.message' ../../tmp/simulation/last-run.json
```

The message contains:

- first invalid entry index
- field path (for example `$.duration_ms`)
- reason (type mismatch / missing required field / invalid JSON)

## Baseline Diff Validation (G4)

Run two consecutive executions with identical pack/config:

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml \
  --mode fixture \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl > ../../tmp/simulation/run-1.json

mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml \
  --mode fixture \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl > ../../tmp/simulation/run-2.json
```

Inspect classification:

```bash
jq -r '.metrics.baseline_diff_report.classification' ../../tmp/simulation/run-2.json
```

## CI and Nightly Operationalization (G5)

`G5` status depends on operational mode:

- `local`: `not_applicable`
- `ci`: `pass`
- `nightly`: `pass` when `--nightly-trend-report` is provided

Local emulation:

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml \
  --mode replay \
  --operational-mode ci \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl > ../../tmp/simulation/ci-run.json
```

GitHub workflows:

- CI readiness gate: [`.github/workflows/simulation-readiness-ci.yml`](../.github/workflows/simulation-readiness-ci.yml)
- Nightly trend pipeline: [`.github/workflows/simulation-readiness-nightly.yml`](../.github/workflows/simulation-readiness-nightly.yml)
