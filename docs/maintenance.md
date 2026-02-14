# Dependency and Runtime Maintenance

## Runtime

Agent uses `mise` for project runtime management.

- Ruby is pinned in `.mise.toml` for reproducible development.
- Update policy: bump to latest stable Ruby after verification with test + lint gates.
- Commands below are run from `runtimes/ruby`.

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
