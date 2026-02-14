# Ubiquitous Language

This project uses the following canonical language for LLM-to-LLM problem solving.

## Core Terms

- `Solver`: the main LLM/Agent that owns the problem and final answer.
- `Specialist`: a delegated LLM/Agent focused on a sub-problem.
- `Delegate`: one Solver action that invokes a Specialist.
- `Outcome`: normalized result of a delegation (success or failure envelope).
- `Synthesis`: Solver reasoning step that combines delegation outcomes and chooses next actions.
- `Delegation Budget`: runtime limit on delegation depth/volume for one solving flow.

## Why These Terms

- They encode intent (problem solving) rather than mechanism (orchestration).
- They remain valid across domains (math, coding, analysis, debate, planning).
- They map cleanly to the tolerant delegation interface.

## Language Rules

- Prefer `Solver/Specialist` over `orchestrator/worker`.
- Use `delegate/delegation` consistently in product and API docs.
- Prefer `outcome` over raw exception-only thinking in tolerant workflows.

## Primitive Usage

- `Agent.for(...)`: bootstrap a top-level Solver or an intentionally independent agent session.
- `solver.delegate(...)`: summon Specialists during active solving while inheriting Solver runtime contract.

See `docs/delegate-vs-for.md` for scenario-level guidance.
