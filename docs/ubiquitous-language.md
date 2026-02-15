# Ubiquitous Language

This project uses the following canonical language for LLM-to-LLM problem solving.

## Core Terms

- `Tool Builder`: the main LLM/Agent that owns the problem and final answer.
- `Tool`: a delegated LLM/Agent focused on a sub-problem.
- `Delegate`: one Tool Builder action that invokes a Tool.
- `Outcome`: normalized result of a delegation (success or failure envelope).
- `Synthesis`: Tool Builder reasoning step that combines delegation outcomes and chooses next actions.
- `Delegation Budget`: runtime limit on delegation depth/volume for one solving flow.

## Dependency and Environment Terms

- `GeneratedProgram`: tool-generated execution payload containing `code` and optional `dependencies`.
- `Dependency Manifest`: normalized list of gem requirements declared by a tool.
- `Environment Manifest`: the dependency manifest frozen for one tool runtime environment.
- `Environment ID (env_id)`: deterministic hash identity for a resolved Ruby execution environment.
- `Monotonic Manifest Growth`: environment manifest may add dependencies over time but MUST NOT remove or mutate existing constraints.
- `Worker`: isolated Ruby execution process bound to one tool environment.
- `Worker Supervisor`: parent runtime component that starts, monitors, restarts, and terminates workers.
- `JSON Boundary`: rule that cross-process request/response payloads are JSON-serializable values only.
- `Environment Preparing`: transient runtime state when dependencies are being resolved/materialized.

## Why These Terms

- They encode intent (problem solving) rather than mechanism (orchestration).
- They remain valid across domains (math, coding, analysis, debate, planning).
- They map cleanly to the tolerant delegation interface.

## Language Rules

- Prefer `Tool Builder/Tool` over `orchestrator/worker`.
- Use `delegate/delegation` consistently in product and API docs.
- Prefer `outcome` over raw exception-only thinking in tolerant workflows.
- Use `GeneratedProgram` for provider outputs; avoid saying "raw code response" when dependency metadata is present.
- Use `Dependency Manifest` and `Environment Manifest` consistently (do not conflate declared vs frozen manifests).
- Use `env_id` when referring to deterministic environment identity in logs, outcomes, and docs.
- Use `JSON Boundary` to describe cross-process data contracts for worker execution.

## Primitive Usage

- `Agent.for(...)`: bootstrap a top-level Tool Builder or an intentionally independent agent session.
- `tool_builder.delegate(...)`: summon Tools during active solving while inheriting Tool Builder runtime contract.

See `docs/delegate-vs-for.md` for scenario-level guidance.
