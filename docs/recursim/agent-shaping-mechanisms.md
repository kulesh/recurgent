# Agent Shaping Mechanisms in Recurgent

Recurgent shapes agents through pressure and evidence, not by hardcoding per-task logic.

## Mechanism Map

| Mechanism | Primary Surface | What It Shapes | Typical Signal |
|---|---|---|---|
| Prompt policy + runtime environment model | [`runtimes/ruby/lib/recurgent/prompting.rb`](../../runtimes/ruby/lib/recurgent/prompting.rb) | interface generalization, stance choice, tool reuse behavior | over-specialized methods, delegation loops |
| Delegation contracts | `purpose`, `deliverable`, `acceptance`, `failure_policy` | child-tool IO boundaries and expected behavior | outcome contract mismatches |
| Outcome/guardrail lanes | validation + repair loops | truthfulness, boundary integrity, regeneration behavior | guardrail retry exhaustion |
| Role profiles | shared-state and return-family constraints | sibling-method coherence for role-style agents | continuity violations, drift types |
| Artifact persistence and promotion policy | toolstore/artifact scorecards | what gets reused or held in probation | lifecycle decisions and false holds/promotions |
| Authority/proposal substrate | proposal + approval/apply flows | controlled policy/profile mutation | auditable change history |
| Simulation packs and gates (`G0`-`G5`) | Recursim contracts + ledger | release confidence and evolution pressure | reproducibility, score drift, trace validity |
| Observability and content continuity | JSONL logs + content refs | diagnosis quality and follow-up transform behavior | missing refs, non-canonical history entries |

## How These Mechanisms Work Together

1. A call executes through runtime guardrails and returns an `Outcome`.
2. Observability captures behavior, failures, retries, continuity and lifecycle metadata.
3. Artifact scorecards and role-profile compliance summarize execution reliability/coherence.
4. Simulation runs aggregate this into lane-aware gate/score evidence.
5. Humans (or governed evolution tooling) use evidence to adjust prompts, profiles, thresholds, and pack contracts.

## Shaping vs Prescription

Recurgent defaults to environmental pressure:
- coordination constraints check sibling agreement,
- readiness gates check reproducibility and drift,
- promotion policy ranks observed reliability.

Prescription is explicit and opt-in:
- prescriptive role-profile constraints,
- hard capability boundaries,
- maintainer-approved policy mutations.

This keeps emergence possible while making correctness requirements enforceable when needed.

## High-Leverage Levers for Day-to-Day Iteration

1. Tighten scenario pack oracles before adding more packs.
2. Use replay evidence (`G1`, `G2`) to separate noise from real regressions.
3. Promote deterministic constraints only when coordination pressure is insufficient.
4. Use live-shadow traces to discover real runtime failure classes before changing policy.
