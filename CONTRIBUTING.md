# Contributing to Recurgent

Thanks for contributing. This project is optimized for high-signal changes with clear user value.

## Contribution Preconditions

1. Open or link an approved issue before submitting a PR.
   - Approved means the issue has maintainer label `ready-for-pr` or `accepted`.
2. PRs without a linked issue may be closed without review.
3. One issue per PR. No bulk or drive-by refactors unless explicitly requested by maintainers.
4. Include tests for behavior changes and explain concrete user value.
5. Keep changes scoped and reversible.

## AI/Automation Policy

AI-assisted contributions are allowed only if the submitter:

1. Reviewed and understands every changed line.
2. Ran tests and lint locally for affected runtime(s).
3. Is available to respond to maintainer review.

Low-effort, bulk-generated, or non-responsive AI submissions may be closed.

## Pull Request Requirements

Use the PR template and complete all required sections:

1. Linked issue.
2. Problem and user value.
3. Implementation summary.
4. Verification evidence (tests/lint/manual checks).
5. Scope/intent declaration (no speculative unrelated edits).
6. Acknowledgement of this policy and `CODE_OF_CONDUCT.md`.

PRs missing required fields may fail automated checks.

## Maintainer Triage Policy

Maintainers may close PRs without review when:

1. No linked issue or no clear user value.
2. Duplicate or speculative changes.
3. Required template fields are missing.
4. Contributor is non-responsive.
5. Submission appears to be spam/flooding.

## Development Workflow

1. Use `mise` for tool/runtime setup.
2. Ruby runtime commands:
   - `cd runtimes/ruby`
   - `bundle exec rspec`
   - `bundle exec rubocop`
3. Keep docs and contract artifacts aligned with behavior changes.

## Conduct

All contributors must follow `CODE_OF_CONDUCT.md`.
