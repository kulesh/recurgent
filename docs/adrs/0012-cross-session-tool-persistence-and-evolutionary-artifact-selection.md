# ADR 0012: Cross-Session Tool Persistence and Evolutionary Artifact Selection

- Status: proposed
- Date: 2026-02-15

## Context

Today, forged tools and generated method implementations effectively live in session memory. The runtime can preserve capability within one solve loop, but a restart resets practical capability and forces re-forging.

This conflicts with the stated top-level purpose for depth-0 agents: Tool Builders create durable Tools that compound over time. If capability disappears when the process exits, compounding remains mostly prompt-level intent rather than runtime mechanism.

We need persistence that:

1. Survives process restarts and multi-day usage.
2. Keeps stable identity for tools while allowing implementation evolution.
3. Avoids hard invalidation on unrelated prompt edits.
4. Supports repair/regeneration when persisted implementations fail.
5. Keeps prompt context bounded as tool counts grow.

## Decision

Introduce a cross-session `ToolStore` with two persistence layers and evolutionary selection policy.

### 1. Two Persistence Layers

1. Tool Registry (contract layer)
   - Persists tool identity and delegation contract metadata.
   - Answers: "what this tool is supposed to do."
2. Method Artifact Store (implementation layer)
   - Persists generated Ruby implementations and execution metadata per tool method.
   - Answers: "how this method currently does it."

The contract layer and artifact layer are decoupled so implementation can evolve without destroying tool identity.

### 2. Stable Tool/Method Identity

Artifact lookup identity key is:

- `role + method_name`

`prompt_version` is NOT part of the lookup key.

`prompt_version` is stored as metadata and used as a staleness/evolution signal, not hard cache invalidation.

### 3. Metadata and Fingerprints

Registry entry includes:

- `role`
- `purpose`
- `deliverable`
- `acceptance`
- `failure_policy`
- `created_at`
- `last_used_at`
- `usage_count`

Method artifact includes:

- `role`
- `method_name`
- `code`
- `dependencies`
- `prompt_version` (metadata)
- `runtime_version`
- `model`
- `code_checksum` (integrity)
- `contract_fingerprint` (staleness heuristic)
- `success_count`
- `failure_count`
- `intrinsic_failure_count`
- `extrinsic_failure_count`
- `recent_failure_rate`
- `last_failure_reason`
- `last_failure_class` (`intrinsic|extrinsic`)
- `created_at`
- `last_used_at`
- `last_repaired_at`
- `repair_count_since_regen`

### 4. Artifact Selection Policy (Execution-Time)

Given `(role, method_name)`:

1. Lookup artifact by stable identity.
2. If missing/corrupt/runtime-incompatible: generate new artifact.
3. If present:
   - If `contract_fingerprint` mismatches current contract: treat as stale and repair/regenerate.
   - If healthy: execute persisted artifact directly.
   - If stale or degraded: try repair flow first.
   - If repair fails or artifact is unhealthy/unproven: regenerate.

Selection is fitness-based, not lineage-based. Prompt mismatch alone does not invalidate proven artifacts.

### 5. Repair Path (Re-Forge)

When persisted code fails:

1. Capture failure context (`error_class`, message, stack snippet, contract, method args signature).
2. Run targeted repair generation with prior code + failure context.
3. Execute repaired candidate.
4. Promote repaired artifact on success; otherwise fall back to full regeneration.
5. Enforce repair budget: if `repair_count_since_regen >= MAX_REPAIRS_BEFORE_REGEN`, skip repair and force full regeneration on next failure.

Repair is preferred before full regeneration to preserve learned implementation structure where possible.
Repair budget prevents indefinite patch-on-patch drift.

### 6. Prompt Version Semantics

`prompt_version` policy:

1. Exact match with current prompt version increases confidence.
2. Mismatch does NOT force regeneration.
3. Mismatch combined with poor health metrics can trigger repair/regenerate.

This prevents wholesale invalidation on prompt refactors while still allowing guided evolution.

### 7. Cross-Session Loading and Runtime Integration

On boot:

1. Load registry from disk into runtime context.
2. Expose loaded tools in `<known_tools>` prompt block.
3. Allow `tool("name")`/`delegate(...)` materialization from persisted contract metadata.

On successful generated execution:

1. Persist/update method artifact.
2. Update usage and health metrics.
3. Update registry recency.

### 8. Lifecycle and Prompt-Size Control

Tool growth is managed through recency-aware injection and pruning:

1. Inject top-N known tools by recency and utility score.
2. Keep full registry on disk; prompt receives bounded working set.
3. Support pruning/archive for unused tools after retention window.

Pruning affects prompt injection priority first, and hard deletion only by explicit policy.

Default generation history retention is `latest + previous 2` artifacts per `(role, method_name)` so runtime can roll back when a repair/regeneration regresses behavior.

### 9. On-Disk Layout

Canonical layout under runtime state/cache root:

```text
tools/
  registry.json
  <role>/
    manifest.json
    <method_name>.json
```

`<method_name>.json` stores both metadata and code payload. Optional `.rb` mirror may be generated for inspection/debugging.

### 10. Observability Additions

Each dynamic call log entry should include:

- `program_source`: `persisted | repaired | generated`
- `artifact_hit`: boolean
- `artifact_prompt_version`
- `artifact_contract_fingerprint`
- `artifact_success_count`
- `artifact_failure_count`
- `artifact_intrinsic_failure_count`
- `artifact_extrinsic_failure_count`
- `repair_attempted`: boolean
- `repair_succeeded`: boolean
- `failure_class`: `intrinsic | extrinsic`

This makes persistence decisions auditable and tunable.

## Consequences

### Positive

1. Tool capability compounds across sessions and over time.
2. Prompt edits do not wipe out working tool behavior.
3. Runtime gains a practical evolutionary loop (execute -> measure -> repair/regenerate).
4. Reduced repeated LLM generation for stable methods.

### Tradeoffs

1. Persistence introduces new state-management complexity.
2. Bad artifacts can persist until detected by health/repair policy.
3. Additional metadata and migration/versioning responsibilities are required.
4. Prompt-context curation becomes a first-class runtime concern.
5. Good artifacts can be prematurely demoted if transient infrastructure failures are misclassified as code defects.

## Alternatives Considered

1. Prompt-version in cache key
   - Rejected: causes full invalidation on prompt changes; poor compounding behavior.
2. No persistence (session-only)
   - Rejected: fails cross-session compounding goal.
3. Persist contracts only, always regenerate method code
   - Rejected: loses runtime efficiency and practical durability.
4. Persist code only, no contract metadata
   - Rejected: loses purpose/acceptance semantics and degrades delegatability.

## Rollout Plan

### Phase 1 (Registry Persistence)

1. Implement `ToolStore` registry read/write.
2. Load registry at startup and hydrate `<known_tools>`.
3. Persist delegated tool contracts from `delegate(...)`/`tool(...)`.

### Phase 2 (Artifact Persistence and Selection)

1. Persist successful generated artifacts by `(role, method_name)`.
2. Add artifact selection path before generation.
3. Add integrity checks and source logging (`persisted|generated`).

### Phase 3 (Repair and Evolution Metrics)

1. Add repair flow for persisted execution failures.
2. Track health metrics (`success_count`, `failure_count`, `recent_failure_rate`).
3. Add staleness heuristics using `prompt_version` and `contract_fingerprint`.
4. Classify failures as intrinsic vs extrinsic and only count intrinsic failures toward regeneration thresholds.
5. Enforce repair budget and forced full regeneration once budget is exhausted.

### Phase 4 (Lifecycle Management)

1. Add recency-ranked known-tools injection.
2. Add pruning/archive policies and maintenance command integration.
3. Add observability dashboards/views for artifact health.

## Guardrails

1. Artifact execution remains subject to existing runtime capability boundaries.
2. Dependency manifests remain validated/normalized under ADR 0010/0011 rules.
3. Persisted artifacts must pass syntax validation before execution.
4. Failed persisted artifacts must not short-circuit tolerant Outcome behavior.
5. Persisted artifacts execute under the same sandbox and capability boundaries as freshly generated code; persistence does not elevate trust or privileges.

## Open Questions

1. Should artifact selection thresholds be global defaults or role-specific?
2. Should registry/artifact writes be immediate, batched, or transaction-journaled?
3. How should utility score be computed for prompt injection ranking (for example, recency-weighted reliability vs exploration-aware approaches)?
4. What retention policy best balances compounding with prompt budget constraints?
