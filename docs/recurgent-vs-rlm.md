# Recurgent vs Recursive Language Models

An assessment of whether Recurgent implements a Recursive Language Model (RLM)
as defined by [Zhang et al. (2025)](https://alexzhang13.github.io/blog/2025/rlm/).

## Verdict

No. Recurgent is a superset that *could* instantiate an RLM as one usage
pattern, but does not implement the RLM framework as described.

## What the Paper Defines

Given query *q* and context *C*, an RLM\_M(q, C) operates over an environment
**E** and can spawn isolated sub-RLM\_M(q̂, Ĉ) instances with transformed
queries and partitioned context. The key insight is **context-centric
recursion** — no single LLM call ever sees the full context. The model writes
code in a REPL environment that partitions context and recursively delegates
subsets to child instances of *itself*. This solves context rot (degradation as
token count increases) and enables scaling to 10M+ tokens.

## Structural Overlap

Both systems share the same execution skeleton:

| Mechanism | RLM | Recurgent |
|---|---|---|
| LLM generates code | Python in a REPL | Ruby via `generate_program` |
| Code executes in environment | Python notebook with pre-loaded context variable | `ExecutionSandbox` with `context` hash binding |
| Code can spawn further LLM calls | `rlm(q̂, Ĉ)` function calls | `delegate(role, ...)` / `tool(name)` / `Agent.for(role)` |
| Results flow back to parent | Return value from sub-RLM | `Outcome` from child Agent |
| Isolated environments | Each sub-RLM gets its own REPL | Each Agent has its own `@context`; each call gets fresh sandbox |
| Depth tracking | Root (depth 0), callees (depth 1+) | `call_frame[:depth]` — 0, 1, 2+ with depth-aware prompting |
| Functional interface | Same API as standard LLM call | Same API as any Ruby method call |

## Critical Differences

### 1. Purpose of recursion

RLM recurses to manage *context windows* — it partitions a massive document set
so no single call is overwhelmed. Recurgent recurses to decompose *tasks* — a
planner delegates to a web fetcher, which is a different role solving a
different problem. The recursion in Recurgent is heterogeneous (different roles
at each level), while RLM recursion is self-similar (same model, same interface,
different context slices).

### 2. Context distribution vs context sharing

The defining property of an RLM is that the root LM "never directly sees the
entire context." Recurgent does the opposite — the full `context` hash is
available to every call. Child agents get their own context, but the parent
passes what it wants explicitly. There is no automatic context partitioning.

### 3. Self-reference

An RLM calls *itself* recursively — `rlm(q̂, Ĉ)` spawns another instance of
the same system. Recurgent's `delegate("web_fetcher")` spawns a *different
agent* with a different role and potentially different behavioral contract. The
prompting explicitly discourages reflexive recursion: "Do NOT delegate
recursively to bypass unavailable capabilities."

### 4. Environment model

RLM's REPL is *stateful and accumulative* — code cells build on each other
within a session. Recurgent's sandbox is *ephemeral* — each call gets a fresh
`ExecutionSandbox`. State persists only through the `context` hash, not through
the execution environment itself.

### 5. Thin wrapper vs full runtime

The paper frames RLM as a "thin wrapper" providing functional equivalence with
standard model calls. Recurgent is a thick runtime with artifact caching,
contract validation, guardrail policies, tool registries, capability pattern
extraction, dependency management, and worker subprocess orchestration.

## What Recurgent Actually Is

Recurgent is an **agent-oriented metaprogramming runtime**. Where RLM asks "how
do I process this massive context?", Recurgent asks "what code should run for
this method call?" The dispatch chain — `method_missing → prompt →
generate_code → eval → Outcome` — turns arbitrary method invocations into
LLM-generated programs, not recursive context decomposition.

The delegation mechanism is closer to **tool-use / multi-agent orchestration**
than to RLM-style recursion. Depth-aware prompting assigns different *roles* at
each depth (Tool Builder → Tool → Worker), which is an agentic hierarchy, not a
recursive self-application.

## Could Recurgent Instantiate an RLM?

Yes, trivially:

```ruby
rlm = Agent.for("recursive_context_processor")
rlm.context_data = massive_document_array
result = rlm.answer("What are the key themes across all documents?")
```

The generated code for `answer` could partition `context[:context_data]`,
delegate subsets to child `Agent.for("context_processor")` instances, collect
their summaries, and synthesize. That would be an RLM running on Recurgent's
infrastructure. But Recurgent does not do this by default — it is one possible
usage pattern within a more general system.

## Summary Table

| Criterion | RLM | Recurgent |
|---|---|---|
| Recursive LLM self-calls | Core mechanism | Supported but not idiomatic |
| Context partitioning | Defining feature | Not present |
| Code generation + execution | Yes (Python REPL) | Yes (Ruby sandbox) |
| Isolated child environments | Yes | Yes |
| Depth-aware behavior | Yes | Yes |
| Task decomposition via delegation | Implicit | Explicit, contract-driven |
| Thin wrapper | Yes | No — full runtime |

Recurgent and RLMs are siblings, not parent-child. They share the "LLM
generates code that spawns further LLM calls" pattern, but diverge on *why* the
recursion happens and *what* gets decomposed. Recurgent decomposes problems;
RLMs decompose contexts.
