# Dependency and Runtime Maintenance

## Runtime

Agent uses `mise` for project runtime management.

- Ruby is pinned in [`.mise.toml`](../.mise.toml) for reproducible development.
- Update policy: bump to latest stable Ruby after verification with test + lint gates.
- Commands below are run from [`runtimes/ruby`](../runtimes/ruby).

## Dependency Update Policy

Run these checks during maintenance:

```bash
cd runtimes/ruby
bundle update --all
bundle outdated
bundle exec rspec
bundle exec rubocop
```

## Current Constraint Notes

As of 2026-02-13:

- `diff-lcs` shows newer `2.x`, but `rspec-expectations` currently constrains `diff-lcs` to `< 2.0`.
- This is an upstream compatibility constraint, not project drift.

Upgrade path:

1. Monitor newer RSpec releases for widened `diff-lcs` support.
2. Upgrade RSpec first.
3. Re-run `bundle update --all` and quality gates.

## Solver Promotion Lifecycle Operations

### Legacy Migration Mode

When an artifact first enters lifecycle tracking from pre-lifecycle data:

1. mark lifecycle root with `legacy_compatibility_mode: true`,
2. initialize current artifact version in `probation` state,
3. require normal v1 evidence window before durable promotion.

This keeps legacy artifacts runnable while forcing policy-based re-qualification.

### Routine Inspection

```bash
# Inspect version scorecards and lifecycle snapshots
bin/recurgent-tools scorecards "<role>" "<method>"

# Inspect recent shadow decisions
bin/recurgent-tools decisions "<role>" "<method>" --limit 25
```

### Manual Lifecycle Override (Audited)

Use only for incident response or rollback:

```bash
# Preview manual override
bin/recurgent-tools set-lifecycle "<role>" "<method>" "<checksum>" degraded --reason "incident rollback"

# Apply manual override
bin/recurgent-tools set-lifecycle "<role>" "<method>" "<checksum>" durable --reason "rollback to stable" --apply
```

Overrides are appended to `lifecycle.manual_overrides` for auditability.

### Rollback Protocol

1. Disable enforcement immediately: set runtime `promotion_enforcement_enabled=false`.
2. Validate user-facing stability on key examples (`calculator`, `assistant`).
3. Inspect shadow decision ledger to locate offending candidate checksums.
4. Optionally force downgrade candidate checksums to `degraded`.
5. Re-enable enforcement only after scorecard and trace review.

## Proposal Operations (ADR 0025)

Proposal artifacts are audited control-plane records. Treat them as immutable history with explicit status transitions only.

### Routine Review

```bash
# Inspect newest proposals
bin/recurgent-tools proposals --limit 50

# Inspect only pending proposals
bin/recurgent-tools proposals --status proposed
```

### Status Transitions

```bash
# Approve / reject
bin/recurgent-tools approve-proposal <proposal_id> --actor <maintainer> --note "reviewed"
bin/recurgent-tools reject-proposal <proposal_id> --actor <maintainer> --note "reason"

# Apply after approval
bin/recurgent-tools apply-proposal <proposal_id> --actor <maintainer> --note "rolled out"
```

Transition rules:

1. `apply-proposal` requires status `approved`.
2. Unauthorized actor receives `authority_denied`.
3. Missing proposal id returns `not_found`.

### Day-2 Incident Handling

1. Snapshot current proposal set (`proposals --limit 200`) before intervention.
2. Apply corrective proposal or reject unsafe pending proposal.
3. Run full tests and example traces.
4. Capture incident notes and resulting proposal ids in maintenance log/PR.

## Context Scope Pressure Review

Run periodic scope-pressure checks for role-heavy tools:

```bash
bin/recurgent-tools namespace-pressure "<role>"
```

Escalate to follow-up ADR drafting when collisions, multi-lifetime usage, and ambiguity-linked continuity violations cross thresholds defined in [`docs/observability.md`](observability.md).
