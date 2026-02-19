# ADR 0023: Solver Shape and Reliability-Gated Tool Evolution

- Status: proposed
- Date: 2026-02-18

## Context

Recurgent already has major reliability building blocks in place:

1. validation-first retries and transactional lifecycle handling (ADR 0016),
2. delegated outcome contract validation (ADR 0014),
3. observational utility semantics (ADR 0017),
4. cross-session artifact persistence and selection (ADR 0012, ADR 0013),
5. boundary referral and cohesion telemetry (`wrong_tool_boundary`, `low_utility`) (ADR 0015).

Recent iteration shows a remaining architectural gap for the next phase:

1. Solver behavior is mostly prompt-policy driven (`Do`, `Shape`, `Forge`, `Orchestrate`) rather than represented as a first-class runtime contract.
2. Automatic tool building works, but "reliable tool" is not yet a single explicit promotion contract with measurable gate criteria.
3. Runtime has rich telemetry, but lacks one canonical solver-level evidence model to drive promotion and evolution decisions deterministically.

This creates avoidable ambiguity:

1. reliability signals are distributed across multiple stores without one promotion-ready envelope,
2. solver intent and solver outcome are not explicitly paired in trace schema,
3. promotion decisions can drift toward heuristics instead of stable lifecycle policy.

This conflicts with project tenets:

1. Agent-first mental model: solver cognition should be inspectable and explicit.
2. Runtime ergonomics for introspection/prescription/evolution: promotion policy should be visible, typed, and auditable.
3. Tolerant interfaces by default: solver interfaces should tolerate partial evidence while preserving stable typed outcomes.
4. Ubiquitous language: Tool Builder/Tool/Worker runtime should have one canonical solver-shape vocabulary.

## Current vs Future (Code Sketches)

### Current State: Stance Mostly Lives in Prompt Policy

Today, stance policy is primarily encoded as prompt text guidance. The model decides behavior from that prose.

```ruby
# runtimes/ruby/lib/recurgent/prompting.rb (simplified)
def _stance_policy_prompt(call_context:)
  depth = call_context&.fetch(:depth, 0) || 0
  return <<~POLICY if depth == 0
    Stance Policy (depth 0):
    - Do
    - Shape
    - Forge
    - Orchestrate
    - If ambiguous between Do and Forge, choose Forge
  POLICY
end
```

Call execution currently treats solver intent as implicit. We execute generated code and log outcomes, but no first-class solver envelope is produced.

```ruby
# runtimes/ruby/lib/recurgent/call_execution.rb (simplified)
def _dispatch_method_call(name, *args, **kwargs)
  system_prompt = _build_system_prompt(call_context: call_context)
  user_prompt = _build_user_prompt(name, args, kwargs, call_context: call_context)
  _execute_dynamic_call(name, args, kwargs, system_prompt, user_prompt, call_context)
end
```

### Future State: Solver Shape Is Explicit Data

Solver intent and decision basis become typed runtime data, logged and persisted with the call.

```ruby
SolverShape = Data.define(
  :stance,                # :do | :shape | :forge | :orchestrate
  :capability_summary,    # String
  :reuse_basis,           # String
  :contract_intent,       # Hash
  :promotion_intent       # :none | :local_pattern | :durable_tool_candidate
)

def build_solver_shape(call_context:, method_name:, known_tools:, contract:)
  SolverShape.new(
    stance: :forge,
    capability_summary: "external_data_retrieval_and_synthesis",
    reuse_basis: "general capability absent from registry",
    contract_intent: contract,
    promotion_intent: :durable_tool_candidate
  )
end
```

### Future State: Promotion Is Reliability-Gated Policy

Automatic tool evolution uses explicit gates and lifecycle transitions.

```ruby
Scorecard = Data.define(
  :calls,
  :contract_passes,
  :contract_failures,
  :guardrail_retry_exhausted,
  :outcome_retry_exhausted,
  :wrong_tool_boundary_count,
  :provenance_violations
)

def durable_gate_v1_pass?(score)
  pass_rate = score.calls.zero? ? 0.0 : score.contract_passes.to_f / score.calls
  pass_rate >= 0.95 &&
    score.guardrail_retry_exhausted.zero? &&
    score.outcome_retry_exhausted <= 1 &&
    score.wrong_tool_boundary_count <= 1 &&
    score.provenance_violations.zero?
end

def next_lifecycle_state(current:, score:)
  return :degraded unless durable_gate_v1_pass?(score)
  return :probation if current == :candidate
  return :durable if current == :probation

  current
end
```

### Future State: Promotion Tracks Artifact Versions, Not Just Tool Names

Promotion state is versioned. New tool implementations compete with incumbents; they do not replace them by default.

```ruby
# Example lifecycle records
# web_fetcher@a1b2c3 => :durable   (incumbent)
# web_fetcher@d4e5f6 => :candidate (new HTML parsing evolution)

def effective_tool_version(tool_name:, versions:)
  durable = versions.find { |v| v.state == :durable && !v.degraded? }
  return durable if durable

  versions.find { |v| v.state == :probation } || versions.first
end

def evaluate_candidate_against_incumbent(candidate:, incumbent:, window:)
  cand = scorecard(candidate, window: window)
  base = scorecard(incumbent, window: window)

  return :promote if durable_gate_v1_pass?(cand) && cand.contract_pass_rate >= base.contract_pass_rate
  return :degrade if cand.guardrail_retry_exhausted > base.guardrail_retry_exhausted

  :continue_probation
end
```

### Reasoning Note: Organism, Not Rigid Type System

This ADR does not propose replacing prompt-policy with a closed planner.

1. Prompt policy remains the primary cognitive surface where Tool Builders reason, adapt, and discover new decompositions.
2. Solver Shape types capture evidence about those decisions so reliability policy can be explicit and auditable.
3. Reliability gates constrain promotion lifecycle, not thought process or domain semantics.

In short: nuanced reasoning stays open-ended; typed fields make evolution legible and governable.

```ruby
# Conceptual layering
# prompt_policy => generates nuanced solver behavior
# solver_shape  => records what happened in stable fields
# gate_policy   => decides promote/probation/degrade using scorecard evidence
#
# The gate reads evidence; it does not author the solver's reasoning.
```

## Decision

Introduce a first-class Solver Shape contract and make automatic tool evolution reliability-gated by explicit policy.

### 1. Solver Shape Becomes First-Class Runtime Data

Each dynamic call should produce a typed Solver Shape envelope that captures:

1. chosen stance (`do`, `shape`, `forge`, `orchestrate`),
2. capability decomposition summary,
3. reuse vs new-tool decision basis,
4. contract intent summary (`purpose`, deliverable strictness hints, failure posture),
5. promotion intent (`none`, `local_pattern`, `durable_tool_candidate`).

This envelope is observational data first. It does not directly mutate domain semantics.

### 2. Reliability Gate Defines Durable Tool Promotion

Tool promotion to durable status must pass explicit reliability gates. V1 gate signals:

1. contract validation pass rate above threshold,
2. no unresolved guardrail-exhaustion pattern for the candidate interface,
3. bounded retry-exhaustion rate,
4. boundary cohesion signal not repeatedly indicating `wrong_tool_boundary`,
5. no unresolved provenance-invariant violations for external-data tools (ADR 0021).

Promotion policy must be deterministic and versioned.

Threshold scope in v1:

1. Start with global default thresholds across capabilities.
2. Introduce capability-class-specific profiles only after trace evidence shows persistent misfit with global defaults.

Initial operating defaults (v1):

1. `probation -> durable` requires at least 10 calls across at least 2 sessions.
2. Coherence signal starts with `state_key_consistency_ratio` as the primary metric.
3. Add richer coherence metrics (for example entropy) only if ratio alone proves insufficient in shadow calibration.
4. Capability-class-specific threshold specialization triggers only when class-level false-hold or false-promotion rate exceeds 2x global average over a meaningful sample.

### 3. Add a Promotion Lifecycle Lane

Tools move through explicit lifecycle states:

1. `candidate`: newly forged or newly reshaped interface,
2. `probation`: reusable and active, but not yet durable-default,
3. `durable`: eligible for default reuse and prompt-injection preference,
4. `degraded`: temporarily down-ranked due to reliability regression.

State transitions are policy-driven by scorecard evidence, not ad hoc runtime rewrites.

Cold-start rule:

1. Keep `candidate -> probation` lightweight so forge-and-use flow remains immediate.
2. Apply stronger evidence gating at `probation -> durable`, not at first productive use.

Lifecycle state is tracked per artifact version, not only per tool name:

1. multiple versions of the same tool may coexist,
2. incumbent durable version remains default during candidate/probation evaluation,
3. promotion replaces default selection only after candidate version clears reliability gate policy,
4. degraded versions are down-ranked without deleting historical traceability.

### 4. Solver Reliability Scorecard Is Canonical

Define a canonical per-tool/per-method reliability scorecard aligned with current telemetry:

1. success and failure counts,
2. contract validation pass/fail counts,
3. guardrail and outcome retry exhaustion counts,
4. user-correction pressure signals,
5. boundary-referral signals,
6. provenance compliance signals when applicable,
7. tool coherence signals (for example shared state-key consistency across sibling methods).

This scorecard is the authoritative input for promotion/demotion lifecycle transitions.

Scorecards are version-scoped and time-windowed so evolving implementations are judged against current durable baselines rather than aggregate lifetime history.

Coherence is treated as an observable property, not a hardcoded type distinction:

1. v1 uses `state_key_consistency_ratio` as the primary coherence input;
2. richer metrics are deferred until trace evidence shows insufficient discrimination;
3. use as promotion input signal, not as standalone rejection unless policy explicitly says so.

### 5. Keep Runtime Semantics Observational

This ADR does not change ADR 0017 semantics:

1. runtime still does not coerce tool-authored success into error by heuristic interpretation,
2. reliability gates influence promotion and reuse preference,
3. boundary validators continue deterministic shape/policy enforcement.

### 6. Continuous Evolution and Re-Promotion

Promotion is not one-time certification.

1. durable tools continue to be re-evaluated as traffic and contexts evolve,
2. newly evolved versions start at `candidate`/`probation`,
3. selector keeps serving incumbent durable until the new version proves reliability,
4. rollback is immediate by re-selecting the prior durable version.

### 7. Tolerant Interface by Default for Solver Envelope

Solver Shape and scorecard boundaries should remain tolerant where practical:

1. symbol/string key tolerance for envelope ingestion and logging,
2. explicit defaults when optional solver fields are absent,
3. strict typing only for promotion gate fields required for deterministic transitions.

## Scope

In scope:

1. first-class Solver Shape envelope in runtime telemetry and persisted evolution metadata,
2. explicit reliability-gated lifecycle states for automatic tool promotion,
3. canonical scorecard contract that drives transition policy.

Out of scope:

1. domain-specific quality heuristics (news/movies/recipes/etc.),
2. runtime-autonomous decomposition that bypasses Tool Builder intent,
3. replacing current delegated contract validation mechanisms.

## Consequences

### Positive

1. "Reliable tool" becomes measurable and auditable.
2. Solver decisions become inspectable in the same vocabulary as architecture docs.
3. Promotion/demotion behavior becomes deterministic and easier to tune safely.
4. Out-of-band evolution pressure uses explicit policy signals instead of diffuse heuristics.

### Tradeoffs

1. Additional schema and policy complexity in artifact/pattern persistence layers.
2. More migration work for traces/tests to include Solver Shape fields.
3. Promotion gates can delay reuse for tools that are useful but under-observed.

## Alternatives Considered

1. Keep solver shape implicit in prompt text only.
   - Rejected: weak introspection and weak policy auditability.
2. Hard-code planner behavior in runtime and reduce Tool Builder discretion.
   - Rejected: conflicts with agent-first and Tool Builder-driven evolution tenets.
3. Promote tools immediately on first successful execution.
   - Rejected: increases fragile-interface persistence and weakens reliability guarantees.

## Rollout Plan

### Phase 1: Schema and Trace Capture (Observational Only)

1. Add Solver Shape envelope fields to call telemetry in non-blocking mode.
2. Persist scorecard primitives from existing counters without changing promotion behavior.

### Phase 2: Policy Contract and Thresholds

1. Define versioned reliability gate policy contract (`v1` thresholds + transition rules).
2. Add policy snapshot/version fields to scorecard and promotion decisions.

### Phase 3: Shadow Promotion Engine

1. Run lifecycle transitions in shadow mode (`candidate` -> `probation` -> `durable`) without affecting runtime reuse.
2. Compare shadow transitions against current selection outcomes to detect regressions.
3. Compare candidate versions against incumbent durable versions for the same tool interface over a fixed observation window.
4. Calibrate thresholds by explicitly tracking false promotions and false holds before enforcement.

### Phase 4: Controlled Enforcement

1. Enable reliability-gated promotion for newly forged tools.
2. Keep existing durable artifacts under compatibility mode until sufficient scorecard evidence is available.
3. Require version-aware switchover and automatic fallback to incumbent durable on regression.

### Phase 5: Prompt and Selector Integration

1. Use lifecycle state and reliability score in known-tools prompt hints.
2. Bias selector toward durable tools and away from degraded tools.

### Phase 6: Acceptance Baselines and Governance

1. Add deterministic acceptance scenarios for promotion/demotion transitions.
2. Publish baseline trace slices demonstrating correct lifecycle state movement.
3. Document operator playbook for threshold tuning and emergency rollback.

## Guardrails

1. Promotion gating must never rewrite domain outcome semantics.
2. Solver Shape remains descriptive/prescriptive metadata, not hidden control flow mutation.
3. Reliability gate policy versions must be explicit and logged.
4. Lifecycle transitions must be reversible and traceable.

## Open Questions

1. How should "meaningful sample" be parameterized operationally (for example minimum evaluations per class and minimum time horizon)?
2. Should session diversity enforce strict session-id uniqueness only, or include additional diversity checks (for example distinct trace segments/time windows)?
