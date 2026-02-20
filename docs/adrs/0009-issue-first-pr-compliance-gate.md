# ADR 0009: Issue-First Pull Request Compliance Gate

- Status: accepted
- Date: 2026-02-13

## Context

Open source repositories are frequently targeted by low-value automated pull requests that consume maintainer review time and CI resources.

## Decision

Adopt an issue-first contribution gate enforced by repository policy and automation:

1. All external PRs must link an approved issue (`ready-for-pr` or `accepted`).
2. PR body must include required sections (problem, value, solution, verification, scope).
3. PR body must include explicit contributor acknowledgements:
   - policy compliance
   - test/lint verification
   - line-level review responsibility
   - code of conduct agreement
4. Non-compliant PRs fail CI via [`.github/workflows/pr-compliance.yml`](../../.github/workflows/pr-compliance.yml).

## Consequences

### Positive

- Reduces low-signal PR volume.
- Preserves maintainer focus for approved roadmap work.
- Creates objective close/no-review criteria for spam and low-effort submissions.

### Tradeoffs

- Adds friction for first-time contributors.
- Requires maintainers to label issues before PR implementation.
