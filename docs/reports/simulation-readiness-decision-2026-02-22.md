# Simulation Readiness Decision (Phase 7a)

- Generated at (UTC): 2026-02-22T03:35:32Z
- Ledger: `../../docs/baselines/2026-02-22/adr-0027/phase-7/run-ledger.jsonl`

## Window Summary

- Required consecutive qualifying runs: 20
- Required distinct seeds: 5
- Required qualifying sessions: 2
- Required distinct UTC days: 3
- Observed consecutive qualifying runs: 20
- Observed distinct seeds: 5
- Observed qualifying sessions: 20
- Observed distinct UTC days: 1

## Gate Status Summary

- This decision is computed from replay entries requiring `G0, G1, G2, G3, G4, G5` to be `pass` for each required pack.
- Required packs: `calculator-core-v1, calculator-edge-v1`
- Qualifying session records analyzed: 20
- Reset events observed: 0

## Evidence Index

- Analysis JSON: `../../docs/baselines/2026-02-22/adr-0027/logs/phase-7a-window-status.json`.
- Decision source ledger: `../../docs/baselines/2026-02-22/adr-0027/phase-7/run-ledger.jsonl`
- Session-level details: included under `session_records` in analysis JSON.

## Unresolved Risks

- Calculator semantic stability gaps remain outside gate mechanics (`solve/history` in example traces).
- External-source variability in assistant scenarios remains class-2 advisory scope.
- Observation window may reset on any class-1 gate failure.

## Readiness Decision

- `class_1_stable: false`
- Rationale:
  - window_met=false
  - trailing_consecutive_qualifying=20
  - distinct_seed_count=5
  - qualifying_session_count=20
  - distinct_day_count=1

## Next Scope Recommendation

- Start class-2 advisory expansion only when `class_1_stable: true` (or explicit maintainer override).
- Keep class-2 packs non-gating during advisory period.
