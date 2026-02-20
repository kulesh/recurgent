# Awareness Substrate and Authority Boundary Implementation Plan

- Status: draft
- Date: 2026-02-19
- Scope: ADR 0025 rollout (`awareness substrate` + `authority boundary`)

## Objective

Implement ADR 0025 so Agent self-awareness is explicit, inspectable, and useful for evolution while mutation authority remains explicitly governed.

Primary outcomes:

1. Awareness is modeled as first-class runtime data (`L1`, `L2`, `L3`).
2. Authority is explicit and bounded (`observe`, `propose`, `enact`), with `enact` denied by default.
3. Proposal artifacts become the canonical path for agent-suggested evolution.
4. Role continuity work from ADR 0024 remains independent and is not diluted by governance/control-plane concerns.

## Non-Goals

1. Do not enable L4 autonomous policy mutation.
2. Do not implement full context storage migration in this plan.
3. Do not merge ADR 0024 continuity mechanics and ADR 0025 governance mechanics into one code path.
4. Do not introduce hidden auto-approval or silent enactment flows.

## Design Constraints

1. Separate awareness from authority in both schema and execution flow.
2. Keep awareness substrate descriptive/read-only in hot path.
3. Keep mutating actions explicit, auditable, and gated by maintainer approval.
4. Preserve backward compatibility for existing runtime/context behavior.
5. Keep rollout evidence-driven; defer broad context-scope migration until trace pressure justifies it.

## Dependency Boundary

Prerequisite alignment:

1. ADR 0024 establishes role/profile continuity semantics and active profile version concepts.
2. ADR 0025 consumes those concepts for awareness visibility and proposal governance.

Execution rule:

1. Land ADR 0024 role-coordination substrate first (or in parallel where non-conflicting).
2. Land ADR 0025 authority enforcement after observational self-model and proposal artifacts are stable.

## Delivery Strategy

Deliver in six phases with explicit go/no-go gates.

### Phase 0: Contract Freeze and Baseline Capture

Goals:

1. Freeze terminology and contracts for awareness levels and authority boundary.
2. Capture baseline traces to compare pre/post awareness visibility.

Implementation:

1. Freeze field contract for `AgentSelfModel`:
   - `awareness_level`
   - `authority`
   - `active_contract_version`
   - `active_role_profile_version`
   - `execution_snapshot_ref`
   - `evolution_snapshot_ref`
2. Define authority defaults:
   - `observe: true`
   - `propose: true`
   - `enact: false`
3. Capture baseline traces from:
   - `examples/calculator.rb`
   - `examples/assistant.rb`
   - one role-profile-enabled flow (ADR 0024 shadow if available)

Suggested files:

1. [`docs/adrs/0025-awareness-substrate-and-authority-boundary.md`](../adrs/0025-awareness-substrate-and-authority-boundary.md)
2. [`docs/observability.md`](../observability.md)
3. `docs/baselines/<date>/...`

Exit criteria:

1. Schema contract documented and unambiguous.
2. Baseline traces stored and reviewable.

### Phase 1: Self-Model Exposure (Observational Only)

Goals:

1. Expose read-only self-model for active calls.
2. Add observability fields without behavior change.

Implementation:

1. Add runtime state carrier for awareness fields.
2. Populate `awareness_level` based on available runtime evidence:
   - `L1`: context/outcomes
   - `L2`: active profile/contract metadata present
   - `L3`: evolution evidence references present
3. Emit self-model snapshot fields to logs.
4. Ensure fields are tolerant for legacy flows (`nil` when absent).

Suggested files:

1. [`runtimes/ruby/lib/recurgent/call_state.rb`](../../runtimes/ruby/lib/recurgent/call_state.rb)
2. [`runtimes/ruby/lib/recurgent/observability.rb`](../../runtimes/ruby/lib/recurgent/observability.rb)
3. [`runtimes/ruby/lib/recurgent/observability_attempt_fields.rb`](../../runtimes/ruby/lib/recurgent/observability_attempt_fields.rb)

Exit criteria:

1. Logs include self-model fields on new calls.
2. No call-path behavior or selection changes.

### Phase 2: Proposal Artifact Protocol

Goals:

1. Define typed proposal artifacts as the only machine path from awareness to potential change.
2. Keep proposals non-mutating by default.

Implementation:

1. Define proposal schema:
   - `proposal_type` (`tool_patch`, `role_profile_update`, `policy_tuning_suggestion`)
   - `target`
   - `evidence_refs`
   - `proposed_diff_summary`
   - `author_context` (agent role/model/trace id)
   - `status` (`proposed`, `approved`, `rejected`, `applied`)
2. Persist proposals in an auditable store.
3. Add operator tooling to inspect/list proposals.

Suggested files:

1. [`runtimes/ruby/lib/recurgent/proposal_store.rb`](../../runtimes/ruby/lib/recurgent/proposal_store.rb) (new)
2. [`runtimes/ruby/lib/recurgent.rb`](../../runtimes/ruby/lib/recurgent.rb) (config/wiring)
3. [`bin/recurgent-tools`](../../bin/recurgent-tools) (proposal inspection commands)
4. [`docs/governance.md`](../governance.md)

Exit criteria:

1. Proposal artifacts are persisted and queryable.
2. No proposal can change runtime policy/profile state without explicit apply action.

### Phase 3: Authority Enforcement

Goals:

1. Enforce `observe/propose/enact` boundary in mutating paths.
2. Emit explicit typed denial on unauthorized enact attempts.

Implementation:

1. Introduce authority checks in all mutating control-plane operations:
   - profile activation/update
   - promotion policy threshold updates
   - governance/ruleset mutations
2. Return typed `authority_denied` outcome with diagnostic context.
3. Preserve denial telemetry for later audit.

Suggested files:

1. [`runtimes/ruby/lib/recurgent/authority.rb`](../../runtimes/ruby/lib/recurgent/authority.rb) (new)
2. [`runtimes/ruby/lib/recurgent/call_execution.rb`](../../runtimes/ruby/lib/recurgent/call_execution.rb)
3. [`runtimes/ruby/lib/recurgent/outcome.rb`](../../runtimes/ruby/lib/recurgent/outcome.rb)
4. [`runtimes/ruby/lib/recurgent/observability.rb`](../../runtimes/ruby/lib/recurgent/observability.rb)

Exit criteria:

1. Unauthorized mutation attempts are denied deterministically.
2. Authorized maintainer apply flow remains functional.

### Phase 4: Governance and Operator Workflow

Goals:

1. Define and document the human-in-the-loop review/apply protocol.
2. Prevent governance ambiguity in day-2 operations.

Implementation:

1. Document review policy:
   - evidence quality requirements
   - approval quorum/ownership rules
   - rollback expectations
2. Add operator commands:
   - `proposals`
   - `approve-proposal <id>`
   - `reject-proposal <id>`
   - `apply-proposal <id>` (maintainer-only)
3. Add governance playbook examples for:
   - role profile update proposal
   - policy tuning suggestion

Suggested files:

1. [`docs/governance.md`](../governance.md)
2. [`docs/maintenance.md`](../maintenance.md)
3. [`bin/recurgent-tools`](../../bin/recurgent-tools)

Exit criteria:

1. Proposal review/apply workflow is documented and executable.
2. Audit trail is complete for approve/reject/apply actions.

### Phase 5: Context Scope Evidence Gate and Follow-Up ADR Trigger

Goals:

1. Decide with evidence whether to launch concrete context-scope migration.
2. Avoid premature substrate expansion.

Implementation:

1. Define evidence thresholds for scope-migration trigger:
   - repeated key-collision incidents,
   - repeated continuity drift attributable to flat namespace pressure,
   - measurable rollback ambiguity from mixed-lifetime keys.
2. Add metrics to observe pressure:
   - key collision count by role
   - same-key multi-lifetime usage count
   - continuity violations linked to namespace ambiguity
3. If trigger met, publish follow-up ADR for storage-level scope migration (`attempt`, `role`, `session`, `durable`).

Suggested files:

1. [`docs/observability.md`](../observability.md)
2. `docs/adrs/<future-context-scope-adr>.md` (only if triggered)

Exit criteria:

1. Either:
   - evidence does not justify migration and decision is documented, or
   - follow-up ADR exists with concrete migration contract.

## Test and Validation Strategy

Per phase, run:

1. Full Ruby test suite (`bundle exec rspec`).
2. Focused specs for new substrate behavior:
   - self-model field presence/absence
   - proposal persistence semantics
   - authority-denied outcomes on unauthorized mutation
3. Acceptance checks:
   - calculator flow for role continuity + awareness telemetry
   - assistant flow for proposal generation trace integrity

Required artifacts:

1. Trace snippets showing awareness fields.
2. Proposal artifact examples (proposed and approved/rejected cases).
3. Authority denial trace with typed outcome.

## Risks and Mitigations

1. Risk: accidental coupling of ADR 0024 and ADR 0025 implementations.
   Mitigation: keep separate modules and separate acceptance tests.
2. Risk: proposal spam/noise from low-signal L3 suggestions.
   Mitigation: minimum evidence thresholds before proposal creation.
3. Risk: hidden backdoor mutation path bypassing authority checks.
   Mitigation: centralize mutating operations through one authority gate module.
4. Risk: context scope migration pressure appears before planned phase.
   Mitigation: add early telemetry in Phase 1/2 to quantify pressure objectively.

## Success Criteria

1. Awareness is visible in runtime artifacts without expanding mutation authority.
2. All mutation actions are auditable and approval-gated.
3. Agents can propose improvements, but cannot auto-apply them.
4. Team can reason about self-awareness mechanics using stable UL terms across docs and code.
