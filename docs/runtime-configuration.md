# Runtime Configuration (Ruby)

This page is the operational reference for `Agent.configure_runtime` and related environment variables.

Primary implementation sources:
- `runtimes/ruby/lib/recurgent/runtime_config.rb`
- `runtimes/ruby/lib/recurgent.rb`

## Why This Matters

Runtime configuration controls:
- dependency resolution policy,
- persistence roots (toolstore + logs),
- lifecycle capture/enforcement switches (promotion, role profiles),
- authority enforcement for proposal apply/rollback flows.

Set configuration **before** creating top-level agents.

```ruby
Agent.configure_runtime(
  toolstore_root: "/tmp/recurgent-tools",
  role_profile_shadow_mode_enabled: true,
  role_profile_enforcement_enabled: false
)
```

## Configure Runtime API

`Agent.configure_runtime(gem_sources:, source_mode:, allowed_gems:, blocked_gems:, **options)`

Dependency policy keys:
- `gem_sources` (`Array<String>`)
- `source_mode` (`"public_only"` or `"internal_only"`)
- `allowed_gems` (`Array<String>|nil`)
- `blocked_gems` (`Array<String>|nil`)

Toolstore/telemetry/evolution keys (`options`):
- `toolstore_root` (`String`)
- `solver_shape_capture_enabled` (`Boolean`)
- `self_model_capture_enabled` (`Boolean`)
- `promotion_shadow_mode_enabled` (`Boolean`)
- `promotion_enforcement_enabled` (`Boolean`)
- `role_profile_shadow_mode_enabled` (`Boolean`)
- `role_profile_enforcement_enabled` (`Boolean`)
- `authority_enforcement_enabled` (`Boolean`)
- `authority_maintainers` (`Array<String>` or comma-delimited `String`)

Unknown `options` keys raise `ArgumentError`.

## Defaults

Defaults come from `Agent.runtime_config`:
- `gem_sources`: `["https://rubygems.org"]`
- `source_mode`: `"public_only"`
- `toolstore_root`: `ENV["RECURGENT_TOOLSTORE_ROOT"]` or XDG default
- `solver_shape_capture_enabled`: `true`
- `self_model_capture_enabled`: `true`
- `promotion_shadow_mode_enabled`: `true`
- `promotion_enforcement_enabled`: `false`
- `role_profile_shadow_mode_enabled`: `true`
- `role_profile_enforcement_enabled`: `false`
- `authority_enforcement_enabled`: `true`
- `authority_maintainers`: from `RECURGENT_AUTHORITY_MAINTAINERS` or current `$USER`

XDG defaults:
- log path: `#{XDG_STATE_HOME:-~/.local/state}/recurgent/recurgent.jsonl`
- toolstore root: `#{XDG_STATE_HOME:-~/.local/state}/recurgent/tools`

## Environment Variables

All booleans accept: `1|true|yes|on` and `0|false|no|off`.

- `RECURGENT_TOOLSTORE_ROOT`
- `RECURGENT_SOLVER_SHAPE_CAPTURE_ENABLED`
- `RECURGENT_SELF_MODEL_CAPTURE_ENABLED`
- `RECURGENT_PROMOTION_SHADOW_MODE_ENABLED`
- `RECURGENT_PROMOTION_ENFORCEMENT_ENABLED`
- `RECURGENT_ROLE_PROFILE_SHADOW_MODE_ENABLED`
- `RECURGENT_ROLE_PROFILE_ENFORCEMENT_ENABLED`
- `RECURGENT_AUTHORITY_ENFORCEMENT_ENABLED`
- `RECURGENT_AUTHORITY_MAINTAINERS`
- `XDG_STATE_HOME` (indirect: log path + default toolstore root)

## Recommended Profiles

### Local Development

```ruby
Agent.configure_runtime(
  promotion_shadow_mode_enabled: true,
  promotion_enforcement_enabled: false,
  role_profile_shadow_mode_enabled: true,
  role_profile_enforcement_enabled: false
)
```

### Continuity Enforcement Trial

```ruby
Agent.configure_runtime(
  role_profile_shadow_mode_enabled: true,
  role_profile_enforcement_enabled: true
)
```

### Governed Proposal Flows

```ruby
Agent.configure_runtime(
  authority_enforcement_enabled: true,
  authority_maintainers: %w[kulesh maintainer2]
)
```

## Verification Checklist

After changing runtime config:
1. run `bundle exec rubocop` and `bundle exec rspec` in `runtimes/ruby`,
2. run `ruby examples/calculator.rb`,
3. run `ruby examples/assistant.rb`,
4. inspect `recurgent.jsonl` per `docs/observability.md`.

## Related Docs

- `docs/architecture.md`
- `docs/observability.md`
- `docs/product-specs/delegation-contracts.md`
- `docs/adrs/0023-solver-shape-and-reliability-gated-tool-evolution.md`
- `docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md`
- `docs/adrs/0025-awareness-substrate-and-authority-boundary.md`
