# Deterministic, Replay, and Live-Shadow

This document explains why Recursim has multiple execution lanes and what each lane is for.

## Why Deterministic Runs Exist

Deterministic fixture/replay runs provide measurement trust.
Without a stable measurement lane, you cannot tell whether a score change is:
- real behavior change,
- environment noise,
- data-source drift,
- scoring bug.

Deterministic lane is the calibration instrument.
Live-shadow lane is the realism instrument.
You need both.

## Lane Model

| Lane | Primary Goal | Typical Inputs | Comparison Rule |
|---|---|---|---|
| Deterministic | reproducibility and stable scoring | fixture artifacts and fixed seeds | payload/score reproducibility |
| Live-Shadow | runtime realism under isolation | scripted real agent calls in run scope | oracle verdict reproducibility |

## What `fixture` and `replay` Mean

- `fixture`: produce baseline artifacts/evidence from a pack.
- `replay`: rerun comparable config to test `G1`/`G2` stability.

For deterministic packs:
- replay expects highly stable outcomes.

For live-shadow packs:
- replay compares oracle verdicts, not raw response text identity.

## What Happens in `live`

When mode is `live`:
1. Runner creates run-scoped isolation paths (`state`, `toolstore`, `tmp`).
2. Scripted scenario steps execute through actual runtime behavior.
3. Outcomes, retries, guardrails, and traces are logged.
4. Oracles evaluate observed outcomes.
5. Lane-aware gate/score evidence is appended to run ledger.

Key property: live-shadow is isolated and advisory-first.
It should not contaminate deterministic baselines.

## Why Call It Live-Shadow

"Live" because it executes real runtime behavior.
"Shadow" because it runs alongside deterministic readiness and remains advisory until proven stable.

## Promotion Discipline

Do not treat live-shadow as gating until observation-window criteria are met.
Typical flow:
1. deterministic class-1 stable,
2. live-shadow advisory window complete,
3. explicit promotion decision record,
4. only then consider broader gating scope.
