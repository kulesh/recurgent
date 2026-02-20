# Governance

## Maintainers

Maintainers own roadmap direction, review standards, release decisions, and enforcement of repository policies.

## Decision Process

1. Small changes: maintainers decide through normal PR review.
2. Architectural changes: record decision in [`docs/adrs/`](adrs).
3. Contract changes: update [`specs/contract/`](../specs/contract) and runtime tests in the same PR.

## Contribution Acceptance Criteria

1. Linked approved issue (`ready-for-pr` or `accepted`).
2. Clear user value and scoped implementation.
3. Passing CI (tests, lint, security checks).
4. Compliance with [`CONTRIBUTING.md`](../CONTRIBUTING.md) and [`CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md).

## Release Authority

Maintainers cut releases and publish release notes/changelog updates.

## Proposal Governance (ADR 0025)

Proposal artifacts are the only machine path from awareness to potential runtime mutation.

### Proposal Lifecycle

1. `proposed`: created by runtime/user tooling with evidence refs.
2. `approved`: maintainer accepts proposal for apply.
3. `rejected`: maintainer declines proposal.
4. `applied`: approved proposal enacted by maintainer.

### Evidence Quality Requirements

A proposal must include:

1. clear target (`tool`, `role_profile`, or `policy` identifier),
2. concrete evidence refs (`trace`, `scorecard`, or incident log),
3. concise diff summary describing expected behavioral impact,
4. rollback note (or explicit statement that no rollback path is required).

### Approval and Ownership Rules

1. Maintainer authority is required for `approve`, `reject`, and `apply`.
2. Standard proposals require one maintainer approval.
3. Policy-tuning proposals require one approving maintainer plus one additional maintainer acknowledgment in PR/discussion notes before release.
4. Proposal actor identity must be preserved in artifact `last_action`.

### Rollback Expectations

1. Every applied proposal must have a rollback strategy documented in the same change set.
2. If regression appears, maintainer reverts behavior by:
   - rejecting follow-up proposal attempts that reintroduce failing behavior,
   - applying corrective proposal or lifecycle override,
   - recording incident outcome in maintenance notes.

### Operator Command Surface

```bash
# List proposals
bin/recurgent-tools proposals [--status proposed] [--limit 25]

# Review decision
bin/recurgent-tools approve-proposal <proposal_id> --actor <maintainer> --note "evidence reviewed"
bin/recurgent-tools reject-proposal <proposal_id> --actor <maintainer> --note "insufficient evidence"

# Enact approved proposal
bin/recurgent-tools apply-proposal <proposal_id> --actor <maintainer> --note "rollout phase 1"
```

### Playbook Examples

Role profile update proposal:

1. verify continuity drift evidence (`state_key_consistency_ratio`, trace failures),
2. approve with note referencing target profile version,
3. apply in controlled rollout, then run calculator + assistant validation.

Policy tuning proposal:

1. verify false-hold/false-promotion trends and sample size,
2. collect second maintainer acknowledgment,
3. apply, monitor shadow/effective decisions, and document rollback trigger.

## Promotion Policy Governance

### Policy Versioning

Promotion gate changes must be versioned (for example `solver_promotion_v1` -> `solver_promotion_v2`).

Required for policy version bumps:

1. ADR update describing motivation and threshold deltas.
2. Implementation plan update with rollout and rollback controls.
3. Shadow-mode evidence showing impact vs previous policy.

### Threshold Change Acceptance Criteria

Threshold changes must include explicit evidence for all of:

1. false-promotion rate trend,
2. false-hold rate trend,
3. fallback frequency trend,
4. user-correction impact trend.

Specialized capability-class thresholds are allowed only when class misfit (false-hold or false-promotion) is consistently >2x the global baseline over a meaningful sample.

### Emergency Controls

Maintainers may temporarily:

1. disable enforcement globally,
2. force lifecycle overrides for specific checksums (`durable` or `degraded`),
3. rollback to prior policy version.

All emergency actions must be auditable in artifact lifecycle metadata and summarized in follow-up notes.
