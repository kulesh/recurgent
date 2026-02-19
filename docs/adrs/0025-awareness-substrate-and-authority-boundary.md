# ADR 0025: Agent Awareness Substrate and Authority Boundary

- Status: proposed
- Date: 2026-02-19

## Context

ADR 0023 establishes reliability evidence and lifecycle policy. ADR 0024 establishes role coordination and continuity constraints. The remaining foundational question is how much self-awareness an Agent should have, and what authority that awareness grants.

Current runtime behavior is strong but implicit:

1. context and outcomes are observable during calls,
2. guardrail/retry lanes enforce repair semantics,
3. evolution evidence exists in scorecards and lifecycle state.

What is missing is one explicit substrate contract that answers:

1. what an Agent can know about itself,
2. what an Agent can propose changing,
3. what an Agent can actually change.

Without this boundary, self-awareness risks drifting into hidden self-mutation.

## Decision

Adopt a bounded reflective model: separate awareness from authority.

Design rule:

1. Agents may observe runtime state and propose changes.
2. Agents must not mutate policy, profile, or governance rules without explicit maintainer approval.

This ADR defines the awareness substrate and authority boundary only. It does not redefine role continuity contracts from ADR 0024.

## Awareness Levels

### L1: Observational

Agent can inspect runtime context and outcomes for the active flow.

### L2: Contract-Aware

Agent can inspect active role/profile contract and continuity constraints for its calls.

### L3: Evolution-Aware

Agent can inspect accumulated reliability/continuity evidence and produce upgrade proposals (tool/profile/prompt-policy proposals).

### L4: Autonomous Policy Mutation

Agent can directly mutate policy/profile/governance rules.

Decision:

1. support L1-L3,
2. explicitly exclude L4.

## Substrate Model

Define five explicit substrates and classify current status:

1. Context Substrate: call/session memory surfaces and state access conventions. Mostly present today; scope boundaries are not yet explicit.
2. Execution Substrate: guardrails, retries, rollback, and attempt lifecycle. Present today (ADR 0014/0016/0022).
3. Evolution Substrate: scorecards, lifecycle states, and reliability evidence. Present today (ADR 0023).
4. Role Coordination Substrate: sibling-method coherence contracts. Introduced by ADR 0024.
5. Contract Substrate: explicit active profile/contract versioning. Introduced by ADR 0024 and strengthened here as part of awareness semantics.

This organizes existing mechanics into first-class architecture vocabulary rather than introducing a new runtime tower.

## Authority Boundary

Awareness and authority are orthogonal.

```ruby
Authority = Data.define(:observe, :propose, :enact)

DEFAULT_AGENT_AUTHORITY = Authority.new(
  observe: true,
  propose: true,
  enact: false
)
```

Agent capabilities under this ADR:

1. `observe`: read context, contracts, outcomes, scorecards, lifecycle telemetry.
2. `propose`: emit typed proposal artifacts (`tool_patch`, `role_profile_update`, `policy_tuning_suggestion`).
3. `enact`: disabled by default; requires explicit maintainer action.

```ruby
def apply_proposal!(proposal, actor:)
  raise "authority_denied" unless actor.maintainer? && actor.explicit_approval?

  proposal_registry.apply!(proposal)
end
```

## Self-Model Contract

Expose one inspectable self-model envelope to support L1-L3 awareness.

```ruby
AgentSelfModel = Data.define(
  :awareness_level,            # :l1 | :l2 | :l3
  :authority,                  # Authority
  :active_contract_version,    # Integer|nil
  :active_role_profile_version,# Integer|nil
  :execution_snapshot_ref,     # trace pointer
  :evolution_snapshot_ref      # scorecard/lifecycle pointer
)
```

This envelope is descriptive. It does not grant mutation rights.

## State Scope Direction (Context Substrate)

Current context is mostly flat (`context[:value]`, `context[:conversation_history]`, `context[:tools]`). This ADR defines target scope vocabulary but does not require full migration now.

Target scope vocabulary:

1. `attempt`: discarded on retry rollback,
2. `role`: shared across sibling methods in a role,
3. `session`: survives within one user session,
4. `durable`: persisted across sessions/artifact lifecycle.

```ruby
# target model sketch (not immediate migration mandate)
context.scope(:role)[:accumulator] = 8
context.scope(:session)[:conversation_history] << turn
context.scope(:attempt)[:scratch] = parse_result
```

Rationale:

1. reduces key-collision/drift pressure in flat context namespaces,
2. clarifies durability and rollback semantics,
3. aligns role continuity with explicit state surfaces.

## Current vs Post-ADR Adoption

### Current

```ruby
# agent has implicit awareness and implicit authority assumptions
context[:value] = 5
context[:conversation_history] = [...]
# no explicit authority boundary for contract/policy mutation semantics
```

### Post-ADR

```ruby
self_model = agent.self_model
# => awareness_level: :l2, authority: { observe: true, propose: true, enact: false }

proposal = agent.propose_role_profile_update(evidence: drift_report)
# proposal artifact is persisted/reviewable
# runtime does not auto-activate proposal without explicit approval
```

## Scope

In scope:

1. awareness level model (L1-L3 supported, L4 excluded),
2. explicit authority boundary contract (`observe`, `propose`, `enact`),
3. canonical substrate vocabulary and self-model envelope.

Out of scope:

1. immediate full context-scope storage migration,
2. auto-approval workflows for proposal enactment,
3. replacing ADR 0024 role continuity semantics.

## Consequences

### Positive

1. self-awareness becomes explicit and auditable.
2. evolution remains active without hidden policy self-mutation.
3. architecture separates coordination/runtime behavior from governance authority.

### Tradeoffs

1. additional model/schema/documentation surface.
2. proposal review workflow becomes a required operational loop.
3. some evolution steps are slower by design due to explicit approval boundary.

## Alternatives Considered

1. keep awareness implicit in prompt-policy only.
   - Rejected: not auditable, authority leakage risk.
2. permit autonomous policy/profile mutation (L4).
   - Rejected: conflicts with governance tenets and control-plane safety.
3. merge this decision into ADR 0024.
   - Rejected: mixes role continuity mechanics with cross-cutting governance substrate; higher review and rollout risk.

## Rollout Plan

### Phase 1: Vocabulary and Envelope (Observational)

1. add self-model envelope fields to observability and docs,
2. expose awareness level and authority state as read-only runtime data.

### Phase 2: Proposal Artifact Protocol

1. define typed proposal artifacts for tool/profile/policy suggestions,
2. persist proposal artifacts with evidence links.

### Phase 3: Authority Enforcement

1. enforce explicit approval gate for enact actions,
2. emit typed `authority_denied` outcomes for unauthorized mutation attempts.

### Phase 4: Context Scope Follow-Up

1. evaluate trace evidence from ADR 0024 rollout and calculator flows,
2. if key-collision pressure persists, publish follow-up ADR for concrete context-scope storage migration.

## Guardrails

1. awareness fields are descriptive and read-only in hot path.
2. proposal generation must not auto-enact.
3. L4 autonomous mutation remains prohibited unless superseding ADR explicitly changes this.
4. role continuity enforcement remains governed by ADR 0024, not redefined here.

## Ubiquitous Language Additions

This ADR introduces canonical terms to add to `docs/ubiquitous-language.md`:

1. `Awareness Level`
2. `Authority Boundary`
3. `Agent Self Model`
4. `Context Substrate`
5. `Role State Channel`
6. `Active Contract Version`
