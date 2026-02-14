# ADR 0011: Environment Cache Policy Identity and Effective-Manifest Execution

- Status: accepted
- Date: 2026-02-14

## Context

The dependency environment contract from ADR 0010 requires deterministic and policy-safe environment reuse. Two implementation gaps emerged:

1. Environment identity and cache-hit checks did not include source policy (`source_mode`, `gem_sources`), allowing cache reuse across different policy configurations.
2. Execution routing used per-call dependency declarations instead of the specialist's resolved effective manifest, so a call could run inline even after the specialist had already adopted a non-empty environment manifest.

In addition, the dynamic-call orchestration path in `lib/recurgent.rb` had grown large enough to reduce clarity for future maintenance.

## Decision

1. `EnvironmentManager#env_id_for` includes normalized source policy:
   - `source_mode`
   - normalized/sorted `gem_sources`
2. Environment cache-hit validation requires policy metadata match in `.ready.json`:
   - `source_mode`
   - normalized/sorted `gem_sources`
   - existing manifest + lock checksum checks remain required.
3. Dynamic execution routing follows the effective manifest after monotonic manifest resolution:
   - if effective manifest is non-empty, execution remains worker-backed even when current call omits dependencies.
4. Dynamic-call orchestration is extracted into `Agent::CallExecution` to keep the core `Agent` file focused on public surface and shared internals.

## Consequences

1. Source-policy changes now force a distinct environment identity and prevent accidental cross-policy cache reuse.
2. Specialist execution behavior is deterministic across calls and aligned with the persisted manifest contract.
3. Core runtime code is easier to reason about and maintain without changing public API behavior.
