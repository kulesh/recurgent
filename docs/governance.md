# Governance

## Maintainers

Maintainers own roadmap direction, review standards, release decisions, and enforcement of repository policies.

## Decision Process

1. Small changes: maintainers decide through normal PR review.
2. Architectural changes: record decision in `docs/adrs/`.
3. Contract changes: update `specs/contract/` and runtime tests in the same PR.

## Contribution Acceptance Criteria

1. Linked approved issue (`ready-for-pr` or `accepted`).
2. Clear user value and scoped implementation.
3. Passing CI (tests, lint, security checks).
4. Compliance with `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md`.

## Release Authority

Maintainers cut releases and publish release notes/changelog updates.
