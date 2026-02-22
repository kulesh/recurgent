# Tutorial: Evolving a Scientific Calculator with Recursim

This tutorial walks through a disciplined loop for evolving calculator behavior from basic arithmetic to scientific coverage.

## Goals

- keep measurement trustworthy,
- improve capability breadth,
- avoid regressions while adding new behavior.

## Prerequisites

- repository set up (`mise`, Ruby deps),
- working knowledge of [`docs/simulation-readiness.md`](../simulation-readiness.md),
- provider key set for live-shadow steps.

## Step 0: Establish Baseline Class-1 Evidence

Run core deterministic pack:

```bash
cd runtimes/ruby
mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml \
  --mode fixture \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl \
  > ../../tmp/simulation/calculator-core-fixture.json

mise exec -- ruby bin/recurgent-sim \
  --pack ../../specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml \
  --mode replay \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl \
  > ../../tmp/simulation/calculator-core-replay.json
```

Inspect gate snapshot:

```bash
jq '{g0:.gates.G0.status,g1:.gates.G1.status,g2:.gates.G2.status,score:.score_vector}' \
  ../../tmp/simulation/calculator-core-replay.json
```

Expected:
- `G0=pass`,
- `G1=pass` on stable replay,
- `G2` may start as advisory until comparable replay exists.

## Step 1: Add Scientific Capability Contract Pressure

Create an experiment pack by extending calculator coverage (example: trig).
Start from existing class-1 pack and add new scripted oracle steps.

```bash
cp ../../specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml \
  ../../tmp/simulation/calculator-scientific-experiment-v1.yaml
```

Edit `../../tmp/simulation/calculator-scientific-experiment-v1.yaml` and add scenario expectations like:

```yaml
oracles:
  - id: trig-sin-0
    expect:
      equals: 0.0
      tolerance: 0.0001
```

Keep each new oracle narrow and measurable.

## Step 2: Run Deterministic First

Run fixture/replay on experiment pack:

```bash
mise exec -- ruby bin/recurgent-sim \
  --pack ../../tmp/simulation/calculator-scientific-experiment-v1.yaml \
  --mode fixture \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl \
  > ../../tmp/simulation/calculator-scientific-fixture.json

mise exec -- ruby bin/recurgent-sim \
  --pack ../../tmp/simulation/calculator-scientific-experiment-v1.yaml \
  --mode replay \
  --fixture-root ../../tmp/simulation/fixtures \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl \
  > ../../tmp/simulation/calculator-scientific-replay.json
```

Why first deterministic:
- verifies your new oracle contract is coherent,
- prevents chasing live noise caused by a bad pack.

## Step 3: Run Live-Shadow for Runtime Reality

```bash
mise exec -- ruby bin/recurgent-sim \
  --pack ../../tmp/simulation/calculator-scientific-experiment-v1.yaml \
  --mode live \
  --live-shadow-root ../../tmp/simulation/live-shadow \
  --ledger-path ../../tmp/simulation/run-ledger.jsonl \
  > ../../tmp/simulation/calculator-scientific-live.json
```

Inspect lane-aware output:

```bash
jq '{lane:.execution_lane,run_scope_id:.run_scope_id,gates:.gates,score:.score_vector}' \
  ../../tmp/simulation/calculator-scientific-live.json
```

## Step 4: Diagnose Failures from Trace + Generated Code

Find run trace:

```bash
find ../../tmp/simulation/live-shadow -name recurgent.jsonl | tail -n 1
```

Inspect step failures:

```bash
jq -r '[.timestamp,.role,.method,.attempt_id,.attempt_stage,.outcome_status,.outcome_error_type] | @tsv' \
  <trace-path>
```

Inspect generated code for failing methods:

```bash
jq -r 'select(.method=="solve" or .method=="sin") | .code' <trace-path>
```

Use this evidence to decide if you need:
- prompt-policy refinement,
- role-profile constraint update,
- guardrail-policy change,
- pack/oracle correction.

## Step 5: Apply a Small Change and Re-Run

After each change:
1. run full test/lint locally,
2. rerun deterministic pack,
3. rerun live-shadow pack,
4. compare score vector and gate status.

Compare recent ledger entries:

```bash
tail -n 10 ../../tmp/simulation/run-ledger.jsonl | jq '{pack_id:.pack_id,lane:.execution_lane,gates:.gates,score:.score_vector.overall,at:.timestamp}'
```

## Step 6: Promote by Evidence, Not Anecdote

Promotion checklist:
- deterministic gates stable,
- replay consistency demonstrated,
- live-shadow advisory trend improving,
- failure signatures understood,
- no new critical regressions in baseline packs.

Only then promote the new pack or behavior profile into regular readiness workflow.

## Typical Anti-Patterns

- Expanding pack scope before deterministic stability.
- Treating one successful live run as proof.
- Changing runtime semantics and pack oracles in the same commit.
- Promoting live-shadow to gating before observation window criteria are met.
