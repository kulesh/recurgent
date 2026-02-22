# Release Process

## Versioning

Recurgent uses Semantic Versioning.

## Release Checklist

1. Ensure [`runtimes/ruby`](../runtimes/ruby) test and lint suites pass.
2. Ensure class-1 simulation readiness gates (`G0`-`G5`) pass in CI for current `main` (`.github/workflows/simulation-readiness-ci.yml`).
3. Confirm docs/contracts are aligned with runtime behavior.
4. Update [`CHANGELOG.md`](../CHANGELOG.md).
5. Tag release as `vX.Y.Z`.
6. Publish release notes summarizing:
   - behavior changes
   - compatibility notes
   - migration notes (if any)

## Post-Release

1. Monitor issues for regressions.
2. Label and prioritize follow-up fixes.
