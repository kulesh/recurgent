# Dependency Environment Implementation Plan

## Objective

Implement ADR 0010 with a phased, low-regret rollout:

1. Specialists can declare dependencies in `GeneratedProgram`.
2. Runtime can validate, normalize, and log dependency manifests.
3. Runtime can materialize Ruby gem environments with deterministic identity.
4. Runtime can eventually execute in isolated workers with JSON-only IPC boundaries.

## Scope

In scope:

1. Provider output contract evolution (`code` -> `GeneratedProgram`).
2. Dependency manifest normalization and compatibility checks (monotonic growth).
3. Runtime source/policy configuration (`gem_sources`, `allowed_gems`, `blocked_gems`).
4. Phase-gated runtime execution architecture (in-process activation, then worker isolation).
5. Typed error taxonomy and observability updates.

Out of scope:

1. Security hardening beyond documented policy controls.
2. Lua runtime implementation (Ruby-only delivery first).
3. Prompt-quality optimization beyond schema/policy compliance nudges.

## Guiding Constraints

1. Preserve Solver/Specialist ubiquitous language and intent-first API.
2. Keep `Agent.for(...)` synchronous.
3. Remove backward-compatibility shims and migrate to `GeneratedProgram` as the only provider output shape.
4. Introduce async preparation only when worker isolation exists (Phase 3).

## Deliverable Map

1. Phase 1 deliverables:
   - `runtimes/ruby/lib/recurgent/generated_program.rb`
   - `runtimes/ruby/lib/recurgent/dependency_manifest.rb`
   - updates to `runtimes/ruby/lib/recurgent/providers.rb`
   - updates to `runtimes/ruby/lib/recurgent/runtime_helpers.rb`
   - updates to `runtimes/ruby/lib/recurgent.rb`
   - tests:
     - `runtimes/ruby/spec/dependency_manifest_spec.rb`
     - updates to `runtimes/ruby/spec/recurgent_spec.rb`
2. Phase 2 deliverables:
   - `runtimes/ruby/lib/recurgent/environment_manager.rb`
   - updates to `runtimes/ruby/lib/recurgent.rb`
   - tests:
     - `runtimes/ruby/spec/environment_manager_spec.rb`
     - updates to `runtimes/ruby/spec/recurgent_spec.rb`
     - updates to `runtimes/ruby/spec/acceptance/recurgent_acceptance_spec.rb`
3. Phase 3 deliverables:
   - `runtimes/ruby/lib/recurgent/worker_executor.rb`
   - `runtimes/ruby/lib/recurgent/worker_supervisor.rb`
   - `runtimes/ruby/lib/recurgent/preparation_ticket.rb`
   - updates to `runtimes/ruby/lib/recurgent.rb`
   - tests:
     - `runtimes/ruby/spec/worker_executor_spec.rb`
     - `runtimes/ruby/spec/worker_supervisor_spec.rb`
     - `runtimes/ruby/spec/preparation_ticket_spec.rb`
     - updates to `runtimes/ruby/spec/acceptance/recurgent_acceptance_spec.rb`

## Phase Plan

## Phase 1: GeneratedProgram + Manifest Semantics (No Materialization)

### Goals

1. Capture and validate dependency declarations.
2. Prove schema reliability and prompt adherence.
3. Add no execution model change for stdlib-only flows.

### Implementation Tasks

1. Provider API evolution:
   - Rename `generate_code(...)` to `generate_program(...)` in provider adapters.
   - Return structured payload only (`{code, dependencies}`).
2. Tool schema update:
   - Add optional `dependencies[]` to runtime helper schema.
3. Introduce `GeneratedProgram` model:
   - parse/validate payload shape.
   - expose `code` and normalized dependencies.
4. Introduce `DependencyManifest`:
   - normalize gem names/versions.
   - detect duplicate/conflicting constraints.
5. Logging update:
   - record `program_dependencies` and `normalized_dependencies`.
6. Error update:
   - add `invalid_dependency_manifest`.

### Test Plan

1. Provider adapter tests:
   - structured payload parse.
2. Manifest tests:
   - normalization and conflict detection.
3. Runtime tests:
   - invalid manifest maps to `Outcome.error` with `error_type=invalid_dependency_manifest`.
4. Acceptance tests:
   - stdlib flows still pass unchanged.

### Exit Criteria

1. No behavior regressions in existing acceptance suite.
2. >95% generated payloads in smoke runs include valid manifest structures (or empty dependencies).
3. New log fields emitted for every dynamic call.

## Phase 2: Environment Materialization + Runtime Policy (In-Process Activation)

### Goals

1. Materialize deterministic gem environments by `env_id`.
2. Enforce runtime source/policy controls.
3. Enforce monotonic manifest growth semantics in execution flow.

### Implementation Tasks

1. `EnvironmentManager`:
   - compute `env_id` from engine/version/patch/platform/manifest.
   - create env dir under `$XDG_CACHE_HOME/recurgent/ruby-envs/<env_id>/`.
   - generate Gemfile using runtime `gem_sources`.
   - run `bundle lock`, `bundle install`.
   - write `.ready` metadata and checksum.
2. Monotonic manifest growth:
   - persist specialist `env_manifest`.
   - allow additive-only growth.
   - reject incompatible mutation with `dependency_manifest_incompatible`.
3. Runtime policy enforcement:
   - add runtime config fields:
     - `gem_sources`
     - `source_mode`
     - `allowed_gems`
     - `blocked_gems`
   - enforce `dependency_policy_violation` before resolve/install.
4. Observability:
   - add `env_id`, `environment_cache_hit`, `env_prepare_ms`, `env_resolve_ms`, `env_install_ms`.

### Test Plan

1. Environment manager tests:
   - deterministic `env_id` including `RUBY_PLATFORM`.
   - cache hit path skips install.
   - lock/install failure mapping.
2. Policy tests:
   - allowlist accept/reject.
   - blocklist reject.
   - source mode behavior (`public_only`, `internal_only`).
3. Integration tests:
   - install once, reuse on second call.
   - additive manifest growth triggers new `env_id`.
   - incompatible mutation (`nokogiri ~> 1.0` -> `nokogiri ~> 2.0`) returns `dependency_manifest_incompatible`.

### Exit Criteria

1. Materialization errors are consistently typed (`dependency_resolution_failed`, `dependency_install_failed`, `dependency_activation_failed`, `dependency_policy_violation`).
2. Warm-path calls avoid install step.
3. Monotonic growth contract verified:
   - additive changes create a new `env_id`.
   - incompatible mutations return `dependency_manifest_incompatible`.

## Phase 3: Worker Isolation + JSON IPC + Supervision

### Goals

1. Remove gem-activation pollution by isolating specialist execution.
2. Enforce JSON-only cross-process boundary.
3. Add worker lifecycle reliability guarantees.
4. Introduce async preparation semantics with `Agent.prepare(...)`.

### Implementation Tasks

1. `WorkerExecutor`:
   - worker boot in env with `bundler/setup`.
   - newline-delimited JSON request/response protocol (`ipc_version`).
2. `WorkerSupervisor`:
   - worker pool/registry keyed by specialist/env.
   - per-call timeout and idle timeout.
   - restart policy and max restart count.
   - cleanup on shutdown (TERM -> KILL escalation, child reaping).
3. JSON boundary enforcement:
   - serialize args/kwargs/result/context.
   - map non-serializable values to `non_serializable_result`.
4. Context migration on env growth:
   - restart worker on `env_id` change.
   - restore serializable context snapshot.
5. Async preparation API:
   - add `Agent.prepare(...) -> PreparationTicket`.
   - implement `status`, `await`, `agent`, `on_ready`, `on_error`.
   - emit `environment_preparing` for calls before readiness.

### Test Plan

1. Worker executor tests:
   - request/response protocol correctness.
   - non-serializable mapping.
2. Supervisor tests:
   - restart behavior.
   - timeout enforcement.
   - max-worker cap.
   - shutdown cleanup.
3. End-to-end tests:
   - specialist survives multiple calls with preserved context.
   - env growth triggers worker restart and continued execution.
4. Preparation ticket tests:
   - lifecycle transitions.
   - callback execution.
   - timeout behavior in `await`.

### Exit Criteria

1. No zombie workers after full test suite.
2. Crash/timeout paths emit typed retriable outcomes (`worker_crash`, `timeout`).
3. JSON boundary is enforced for every worker call.
4. `Agent.prepare` semantics verified with asynchronous readiness and `environment_preparing` outcomes.

## Cross-Cutting Workstreams

### Prompt and Schema Alignment

1. System prompt additions:
   - define `GeneratedProgram` output shape.
   - require `dependencies` entries for all non-stdlib `require` usage.
   - require minimal manifests (declare only actually needed gems).
   - instruct no speculative dependency additions.
2. User prompt additions:
   - include concrete example payload:
     - stdlib-only method: `dependencies: []`
     - gem-backed method: `dependencies: [{name, version}]`.
   - include reminder that dependency declarations are part of the execution contract.
3. Retry prompt additions:
   - if manifest parse fails, include structured corrective feedback (invalid field, conflict, forbidden gem).
   - if policy check fails, require alternative implementation using allowed dependencies or stdlib.
   - if dependency activation fails, prompt specialist to narrow/change dependency set.
4. Prompt verification:
   - add deterministic prompt unit checks that required contract language appears in system/user/retry prompts.

### Documentation and Contracts

1. Update `specs/contract/v1/agent-contract.md` after Phase 1 completion.
2. Add contract scenarios for dependency errors and environment-preparing flow.
3. Keep ADR 0010 as `proposed` until Phase 1 lands; promote status to `accepted` after Phase 2 stability.

### Operational Defaults

1. Default policy stays open for ergonomics:
   - source: `https://rubygems.org`
   - allowlist: none
   - blocklist: none
2. Enterprise deployment can override via runtime config.

## Rollout Strategy

1. Land Phase 1 as the default path (no legacy fallback path retained).
2. Land Phase 2 as the default execution path for dependency materialization.
3. Land Phase 3 as the default execution path for worker isolation.
4. Validate each phase with its exit criteria before beginning the next phase.

## Risks and Mitigations

1. Risk: dependency declaration quality from LLM is noisy.
   - Mitigation: strict validation + retry hints + logging feedback loop.
2. Risk: first-call latency hurts interactive sessions.
   - Mitigation: `Agent.prepare`, env caching, optional prewarm.
3. Risk: worker lifecycle bugs degrade reliability.
   - Mitigation: explicit supervision tests before defaulting to worker mode.

## Change Checklist

1. Phase 1 merged with tests and docs.
2. Phase 2 merged with policy enforcement and monotonic environment behavior.
3. Phase 3 merged with supervisor, JSON boundary, and `Agent.prepare`.
4. Contract docs updated at each phase gate.
5. Observability dashboards/watch tooling can display new environment fields.
