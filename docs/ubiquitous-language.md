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

## Lifecycle and Guardrail Terms

- `Fresh Generation Path`: non-persisted call path that generates code for the current invocation.
- `Pre-Execution Validation`: validation stage between generation and execution that checks syntax/policy/guardrails.
- `Recoverable Guardrail`: policy violation that can be corrected by regenerating code in the same call.
- `Terminal Guardrail`: policy violation that cannot be corrected by regeneration alone (for example missing credentials or unsupported runtime capability).
- `Guardrail Recovery Budget`: bounded retry budget dedicated to recoverable guardrail regeneration.
- `Attempt Isolation`: per-attempt transactional execution boundary that prevents failed-attempt mutations from leaking.
- `Commit on Success`: state mutations from an attempt become durable only after validation + execution succeed.
- `Rollback`: restoration of pre-attempt state when an isolated attempt fails recoverably/terminally.
- `Guardrail Retry Exhausted`: typed terminal outcome when recoverable guardrail retries are consumed.
- `Attempt Stage`: lifecycle stage marker for one attempt (`generated`, `validated`, `executed`, `rolled_back`).

## Evolution Terms

- `Inline Lane`: hot-path correction and typed failure signaling during active calls.
- `Out-of-Band Lane`: asynchronous reflective evolution path over accumulated telemetry.
- `Wrong Tool Boundary`: typed referral that a Tool was asked to cross capability boundaries it should not own.
- `Low Utility`: typed signal that output was structurally valid but semantically weak for intent.
- `User Correction`: high-confidence utility signal from short-window same-topic re-ask behavior.

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
- Use `recoverable_guardrail` by default unless explicitly terminal.
- Use `guardrail_recovery_budget` distinctly from provider generation retries.
- Use `commit on success`/`rollback` language for attempt-local transaction semantics.

## Primitive Usage

- `Agent.for(...)`: bootstrap a top-level Tool Builder or an intentionally independent agent session.
- `tool_builder.delegate(...)`: summon Tools during active solving while inheriting Tool Builder runtime contract.

## Reserved Runtime Method Surface (Ruby)

These method names are runtime primitives on `Agent` and do not flow through dynamic dispatch:

- `tool`
- `delegate`
- `remember`
- `runtime_context`
- `to_s`
- `inspect`
- `define_singleton_method` (guardrail)

Guidance:

- Generated/runtime-evolving tool code should use `context[...]` for state, not host method names.
- Treat `context` as working memory; if model priors prefer `memory`, use local aliasing (`memory = context`) inside generated execution scope only.
- Avoid introducing new public `Agent` methods unless necessary; each new method name shrinks dynamic method namespace.

See `docs/delegate-vs-for.md` for scenario-level guidance.
