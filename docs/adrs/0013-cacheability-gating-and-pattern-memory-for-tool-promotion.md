# ADR 0013: Cacheability Gating and Pattern Memory for Emergent Tool Promotion

- Status: proposed
- Date: 2026-02-15

## Context

ADR 0012 introduced cross-session artifact persistence keyed by:

- `role + method_name`

That identity is correct for durable tool methods (for example, `web_fetcher.fetch_url(url)`), where implementation is stable and inputs are data.

Recent runtime traces exposed a critical failure mode for dynamic dispatcher methods (for example, `assistant.ask(question)`):

1. A query-specific implementation (Google News URL) was persisted.
2. A semantically different query (Yahoo News) reused the persisted implementation.
3. The call executed successfully but returned the wrong source/domain result.

This is not a storage-key problem. It is an execution eligibility problem:

- some artifacts should be persisted for observability and evolution history,
- but must not be reused as executable cache.

At the same time, promotion to durable tools currently relies on the model inferring repetition from per-call context. For non-cacheable dynamic methods, each call is freshly generated, so repetition signal is weak/noisy without runtime-provided memory.

## Decision

Keep artifact identity unchanged (`role + method_name`) and separate:

1. **Artifact persistence** ("should this run be recorded?")
2. **Artifact reuse** ("is this artifact eligible for direct execution?")

by introducing cacheability metadata and pattern-memory prompt injection.

### 1. Keep Stable Artifact Identity

Artifact lookup/storage identity remains:

- `role + method_name`

No shape-specific key expansion is introduced in this ADR.

### 2. Add Artifact Cacheability Metadata

Each method artifact records:

- `cacheable: true|false`
- `cacheability_reason: string`
- `input_sensitive: true|false`

Cacheability is computed at generation/repair time by runtime heuristics:

1. **Dynamic dispatch methods** (for example `ask`, `chat`, `discuss`, `host`) are non-cacheable by default.
2. If code appears input-baked (argument literals embedded into structure), mark non-cacheable.
3. Contracted delegated tool methods are cacheable unless contradicted by (2).
4. Stable methods default to cacheable.

### 3. Gate Reuse in Selector

Persisted artifact execution requires:

1. `cacheable == true` (or legacy-compatible fallback for stable methods),
2. existing runtime/contract/checksum compatibility checks,
3. health checks from ADR 0012.

Non-cacheable artifacts are persisted but never selected for direct execution.

### 4. Legacy Artifact Behavior

For artifacts without cacheability metadata:

1. dynamic dispatch method names are treated as non-cacheable,
2. stable methods continue with existing compatibility checks.

This avoids replaying legacy `ask` artifacts while preserving working stable tools.

### 5. Add Pattern Memory for Promotion (Observation, Not Control)

Runtime will maintain a bounded recent capability-pattern history and inject it into depth-0 prompts:

```xml
<recent_patterns>
  rss_parse: seen 3 of last 5 ask calls, no tool registered
  html_extract: seen 2 of last 5 ask calls, web_fetcher available
</recent_patterns>
```

This is observational scaffolding only:

1. runtime records repetition and exposes signal,
2. model still decides whether/how to Forge.

### 6. Promotion Guidance

Prompt policy should distinguish:

1. domain-specific repetition thresholds (rule-of-3),
2. general capability promotion (promote earlier when repetition is observed, for example 2+ occurrences).

Exact threshold remains runtime-configurable and can evolve with telemetry.

### 7. Optional Model Self-Assessment (Asymmetric Trust)

Runtime may accept an optional model-emitted cacheability hint (for example `cacheable=false`, reason string), but final eligibility remains runtime-owned.

Trust policy is asymmetric:

1. runtime veto always applies (runtime can force non-cacheable),
2. model can veto cacheability (model-declared non-cacheable downgrades reuse),
3. model cannot unilaterally force cacheable execution against runtime heuristics.

## Consequences

### Positive

1. Prevents semantic cache poisoning for dynamic methods.
2. Preserves ADR 0012 identity model and storage layout.
3. Keeps full observability history for non-cacheable methods.
4. Improves chance of emergent promotion by exposing repetition signal.
5. Keeps promotion authority with the agent, not hardcoded runtime automation.

### Tradeoffs

1. Cacheability heuristics can produce false positives/negatives.
2. Pattern taxonomy requires curation to avoid noisy categories.
3. Prompt budget cost increases with pattern injection (bounded window required).
4. Without careful pruning, pattern memory may bias toward recent but low-value patterns.

## Alternatives Considered

1. **Expand artifact key by query/task fingerprint**
   - Rejected: solves one failure mode but conflates identity and reuse policy; increases artifact cardinality and storage complexity.
2. **Disable persistence for dynamic methods entirely**
   - Rejected: loses useful observability/evolution history.
3. **Runtime-autonomous promotion (auto-Forge on repetition)**
   - Rejected: moves core design decision away from the agent; less aligned with emergent tooling philosophy.
4. **No pattern memory injection**
   - Rejected: leaves agent without durable repetition signal under per-call isolation.

## Rollout Plan

### Phase 1: Cacheability Fields and Selector Gate

1. Add `cacheable`, `cacheability_reason`, `input_sensitive` to artifacts.
2. Compute cacheability in generation + repair paths.
3. Enforce cacheability gate in artifact selector.
4. Add observability fields to call logs.

### Phase 2: Legacy Handling and Verification

1. Apply conservative fallback for legacy artifacts (dynamic methods non-cacheable).
2. Add regression tests for:
   - `ask("Google")` then `ask("Yahoo")` must regenerate, not reuse,
   - stable tool methods still reuse persisted artifacts.

### Phase 3: Pattern Memory Injection

1. Record recent capability patterns per role.
2. Inject bounded `<recent_patterns>` block in depth-0 prompt.
3. Track promotion rate and quality changes in observability.
4. Bootstrap capability extraction with deterministic runtime signals first (for example stdlib `require` detection such as `require 'rss'` -> `rss_parse`) before adding semantic classification.

## Guardrails

1. Non-cacheable does not mean non-persistent.
2. Cacheability gate applies only to artifact execution selection.
3. Existing contract/checksum/runtime compatibility checks remain mandatory.
4. Pattern injection must be bounded and deterministic (window + top-N).
5. Runtime provides observations; agent remains final authority for tool promotion and interface design.
6. Pattern memory must not include raw prior code; inject only capability labels, counts, and recency summaries.

## Open Questions

1. What is the minimal useful capability taxonomy for pattern history?
2. What window/decay function gives robust promotion signal without prompt bloat?
3. Should promotion thresholds vary by role/domain?
4. Should cacheability heuristics incorporate explicit model self-assessment in addition to runtime signals, and if so, should asymmetric veto policy be mandatory?
