# ADR 0008: Solver/Specialist Language and Tolerant Delegations

- Status: accepted
- Date: 2026-02-13

## Context

Recurgent is used by LLMs that are actively solving problems, not merely coordinating calls. Language such as "orchestrator" understates that responsibility, and raise-only interfaces make long delegation workflows brittle.

## Decision

Adopt a problem-solving language model and codify tolerant delegation interfaces.

1. Ubiquitous language:
- `Solver`: the main problem-owning LLM/Agent.
- `Specialist`: delegated expert LLM/Agent.
- `Delegate`: one Solver -> Specialist action.
- `Outcome`: normalized result of a delegation.
- `Synthesis`: Solver integrates outcomes and decides next action.
- `Delegation Budget`: runtime limit for delegation depth/volume.

2. Interface model:
- Adopt tolerant outcomes as the canonical dynamic call contract.
- Dynamic calls return `Outcome` envelopes instead of aborting on first failure.
- Keep typed error classes for diagnostics/logging, but callers consume outcomes.

3. Contracting:
- Codify tolerant delegation profile in shared contract artifacts and scenarios so Ruby/Lua remain aligned.

## Consequences

### Positive

- Better cognitive alignment for Solver-driven LLM reasoning.
- More resilient long-running workflows (debates, panel synthesis, research sweeps).
- Shared cross-runtime semantics for failure-tolerant delegation.

### Tradeoffs

- Additional API/contract surface to maintain.
- Callers must reason about `Outcome` envelopes explicitly.

## Rejected Alternatives

1. Keep raise-only semantics.
- Rejected: causes avoidable full-run aborts in multi-delegation workflows.

2. Encode tolerant behavior only in examples.
- Rejected: insufficient for consistent runtime parity and evolution.
