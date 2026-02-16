# Documentation Index

## Core Documents

- `docs/architecture.md` - canonical runtime architecture diagrams (component map, call flow, persistence/repair, dual-lane evolution)
- `docs/onboarding.md` - setup, workflow, quality gates
- `docs/specs/idea-brief.md` - product vision and design intent
- `docs/specs/recursim-product-spec.md` - product specification for Recursim simulator focused on robustness and reliable emergence in self-contained systems
- `docs/ubiquitous-language.md` - canonical Tool Builder/Tool vocabulary
- `docs/tolerant-delegation-interfaces.md` - tolerant delegation design guidance and examples
- `docs/delegate-vs-for.md` - concrete `delegate(...)` vs `Agent.for(...)` decision guide
- `docs/specs/delegation-contracts.md` - Phase 1 Tool Builder-authored Tool contract metadata for both `Agent.for(...)` and `delegate(...)`
- `docs/observability.md` - mechanistic interpretability via shared log schema and live watcher
- `docs/recurgent-implementation-plan.md` - phased plan for LLM-native coordination API and naming transition
- `docs/dependency-environment-implementation-plan.md` - detailed phased implementation plan for ADR 0010 dependency-aware environments
- `docs/cross-session-tool-persistence-implementation-plan.md` - phased implementation plan for ADR 0012 cross-session tool and artifact persistence
- `docs/cacheability-pattern-memory-implementation-plan.md` - phased implementation plan for ADR 0013 cacheability-gated artifact reuse and pattern-memory promotion
- `docs/outcome-boundary-contract-validation-implementation-plan.md` - phased implementation plan for ADR 0014 delegated outcome validation and tolerant interface canonicalization
- `docs/tool-self-awareness-boundary-referral-implementation-plan.md` - phased implementation plan for ADR 0015 dual-lane evolution with `wrong_tool_boundary`, `low_utility`, cohesion telemetry, and user-correction signals
- `docs/validation-first-fresh-generation-implementation-plan.md` - phased implementation plan for ADR 0016 validation-first fresh-call lifecycle, transactional retries, and recoverable guardrail recovery
- `docs/contract-driven-utility-failures-implementation-plan.md` - phased implementation plan for ADR 0017 contract-driven utility failures with observational runtime semantics and out-of-band evolution pressure
- `docs/baselines/2026-02-15/README.md` - pre-persistence baseline traces for assistant and philosophy debate scenarios
- `docs/roadmap.md` - near/mid/long-term roadmap
- `docs/governance.md` - maintainer governance and decision model
- `docs/support.md` - support policy and triage expectations
- `docs/release-process.md` - release process and SemVer policy
- `docs/open-source-release-checklist.md` - OSS launch readiness and manual GitHub settings checklist
- `docs/adrs/README.md` - architecture decision index and status model
- `docs/adrs/0013-cacheability-gating-and-pattern-memory-for-tool-promotion.md` - cacheability-gated artifact execution and pattern-memory-assisted promotion policy
- `docs/adrs/0014-outcome-boundary-contract-validation-and-tolerant-interface-canonicalization.md` - delegated outcome-shape enforcement and tolerant interface canonicalization policy
- `docs/adrs/0015-tool-self-awareness-and-boundary-referral-for-emergent-tool-evolution.md` - Tool self-awareness protocol, boundary-referral outcomes, and cohesion-telemetry-driven evolution policy
- `docs/adrs/0016-validation-first-fresh-generation-and-transactional-guardrail-recovery.md` - validation-first fresh-call lifecycle with recoverable guardrail retries and commit-on-success attempt isolation
- `docs/adrs/0017-contract-driven-utility-failures-and-observational-runtime.md` - runtime stays observational for utility semantics; utility failures come from enforceable contracts and out-of-band evolution pressure
- `docs/maintenance.md` - runtime and dependency maintenance policy
- `CONTRIBUTING.md` - contribution policy and quality gates
- `CODE_OF_CONDUCT.md` - collaboration and anti-spam behavior policy
- `SECURITY.md` - vulnerability reporting policy
- `CHANGELOG.md` - release notes history
- `specs/contract/README.md` - runtime-agnostic contract package
- `specs/contract/v1/agent-contract.md` - normative Agent behavior contract (v1)
- `specs/contract/v1/scenarios.yaml` - shared conformance scenarios (v1)
- `specs/contract/v1/tolerant-delegation-profile.md` - tolerant delegation profile
- `specs/contract/v1/tolerant-delegation-scenarios.yaml` - tolerant delegation scenarios (v1)
- `runtimes/ruby/README.md` - Ruby runtime quick reference
- `runtimes/lua/README.md` - Lua runtime placeholder

## Architecture Overview

The Ruby runtime (`runtimes/ruby`) keeps a narrow architecture:

- `runtimes/ruby/lib/recurgent.rb` - dynamic dispatch, execution, retry, and outcome mapping
- `runtimes/ruby/lib/recurgent/prompting.rb` - system/user prompt construction and tool schema
- `runtimes/ruby/lib/recurgent/observability.rb` - JSONL log entry construction and debug metadata
- `runtimes/ruby/lib/recurgent/call_execution.rb` - dynamic call orchestration and execution path selection
- `runtimes/ruby/lib/recurgent/user_correction_signals.rb` - deterministic temporal re-ask `user_correction` detection and normalization
- `runtimes/ruby/lib/recurgent/outcome.rb` - `Agent::Outcome` envelope model
- `runtimes/ruby/lib/recurgent/providers.rb` - provider adapters (Anthropic/OpenAI)
- `runtimes/ruby/lib/recurgent/dependency_manifest.rb` - dependency declaration normalization
- `runtimes/ruby/lib/recurgent/environment_manager.rb` - environment materialization and cache
- `runtimes/ruby/lib/recurgent/worker_executor.rb` - worker process IPC execution
- `runtimes/ruby/lib/recurgent/worker_supervisor.rb` - worker lifecycle and restart handling
- `runtimes/ruby/lib/recurgent/preparation_ticket.rb` - async environment preparation lifecycle
- `runtimes/ruby/spec/recurgent_spec.rb` - unit/contract tests
- `runtimes/ruby/examples/` - executable behavior demonstrations

## Data Flow

Canonical diagrams live in `docs/architecture.md`.

```mermaid
sequenceDiagram
  participant C as Caller
  participant A as Agent
  participant L as LLM Provider
  participant S as Artifact Selector
  participant W as Worker

  C->>A: missing_method(args, kwargs)
  A->>S: select(role, method, args)
  alt persisted artifact eligible
    S-->>A: artifact code
  else miss / stale / non-cacheable
    A->>L: generate_program(system_prompt, user_prompt, schema)
    L-->>A: { code, dependencies }
  end
  alt dependencies empty
    A->>A: eval(code, binding)
  else dependencies present
    A->>W: execute via JSON IPC
    W-->>A: value/context snapshot
  end
  A-->>C: Outcome
```

## Documentation Rules

- Put all long-form project docs under `docs/`.
- Record architecture decisions in `docs/adrs/`.
- Keep this index updated when adding docs.
