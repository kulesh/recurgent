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

## Role Continuity Terms

- `Role Profile`: explicit, opt-in contract that defines coherence/correctness expectations for a role with sibling methods.
- `Coordination Constraint`: profile constraint that requires sibling methods to converge on one convention (state key or return shape family) without prescribing the exact value.
- `Prescriptive Constraint`: profile constraint that pins an explicit required value (for example `canonical_key: :value`).
- `Canonical State Key`: explicit key required by a prescriptive constraint for a given semantic slot.
- `State Continuity`: property that sibling methods in one role agree on compatible state and return conventions.
- `State Continuity Guard`: validation guard that checks profile-enabled calls for continuity drift and routes violations through recoverable repair lanes.
- `Active Profile Version`: explicit role-profile version bound to a call and used for continuity evaluation.
- `Profile Compliance`: observed pass/fail evidence showing whether generated role behavior matches the active role profile and its constraint modes.
- `Profile Drift`: observed divergence between generated role behavior and declared role profile (for example `:memory` vs `:value` key usage).

## Awareness Substrate Terms

- `Awareness Level`: bounded self-awareness tier (`L1` observational, `L2` contract-aware, `L3` evolution-aware, `L4` autonomous mutation excluded by default).
- `Authority Boundary`: explicit separation between what an Agent can observe/propose and what it can enact.
- `Agent Self Model`: read-only runtime envelope that exposes awareness level, authority state, and active contract/profile versions.
- `Context Substrate`: canonical model for runtime state surfaces and their scope semantics (`attempt`, `role`, `session`, `durable`).
- `Role State Channel`: role-scoped shared state surface used by sibling methods to maintain continuity.
- `Active Contract Version`: explicit contract/profile version bound to a call and used for validation/evolution interpretation.
- `Namespace Pressure`: observable drift signal from flat context usage (key collisions, mixed inferred lifetimes, ambiguity-linked continuity violations).

## Response Content Continuity Terms

- `Response Content Continuity`: ability to reliably reference and transform prior turn substance (text/code/object payload), not just metadata.
- `Content Store`: bounded runtime store for response payloads linked from conversation history.
- `Content Ref`: stable identifier that points to stored response content.
- `Content Ref Resolution`: runtime lookup of payload by `content_ref`.
- `Content Retention Policy`: configured bounds for content continuity (`max_entries`, `max_bytes`, optional TTL).
- `Content Eviction`: deterministic removal policy (for example oldest-first/LRU) when retention bounds are exceeded.

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
- Use `Role Profile` only for explicit role contracts; do not imply runtime inference.
- Default to `Coordination Constraint` when profile needs coherence but not fixed naming/shape.
- Use `Prescriptive Constraint` only when deterministic pinning is required.
- Use `State Continuity` when discussing sibling-method contract coherence.
- Separate awareness from authority: allow observe/propose by default, require explicit approval for enact.
- Keep response-content continuity separate from conversation-history metadata continuity.

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

See [`docs/delegate-vs-for.md`](delegate-vs-for.md) for scenario-level guidance.
