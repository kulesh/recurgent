# Release Process

## Versioning

Recurgent uses Semantic Versioning.

## Release Checklist

1. Ensure [`runtimes/ruby`](../runtimes/ruby) test and lint suites pass.
2. Confirm docs/contracts are aligned with runtime behavior.
3. Update [`CHANGELOG.md`](../CHANGELOG.md).
4. Tag release as `vX.Y.Z`.
5. Publish release notes summarizing:
   - behavior changes
   - compatibility notes
   - migration notes (if any)

## Post-Release

1. Monitor issues for regressions.
2. Label and prioritize follow-up fixes.
