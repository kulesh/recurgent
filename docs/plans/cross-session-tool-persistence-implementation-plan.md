# Cross-Session Tool Persistence Implementation Plan

## Objective

Implement ADR 0012 so Tool and method capabilities persist across sessions and evolve based on runtime fitness rather than prompt lineage.

This plan turns "Tool Builders create durable Tools that compound over time" into a concrete runtime mechanism.

## Scope

In scope:

1. Cross-session persistence for tool registry metadata.
2. Cross-session persistence for method artifacts (`role + method_name` identity).
3. Artifact selection, repair, and regeneration policy with intrinsic/extrinsic/adaptive failure classification.
4. Recency-bounded known-tools prompt injection and pruning lifecycle.
5. Observability and maintenance operations for persisted artifacts.

Out of scope:

1. Lua runtime parity.
2. Provider-specific optimization beyond existing schema contract.
3. New external storage systems (SQLite/Postgres); initial implementation remains file-based.

## Design Constraints

1. Stable artifact identity is `role + method_name`.
2. `prompt_version` is metadata/staleness signal, not a lookup key.
3. Persisted artifacts do not receive elevated trust, privileges, or capabilities.
4. Existing dependency/environment contracts from ADR 0010/0011 remain authoritative.
5. Tolerant `Outcome` semantics remain the dynamic-call contract.
6. File persistence uses atomic write semantics to avoid partial artifacts under concurrent writers.

## Delivery Strategy

Deliver in six incremental phases. Each phase is independently shippable and testable.

### Baseline Capture (Pre-Phase 0)

Goals:

1. Capture deterministic before-persistence traces for comparison.
2. Preserve prompt/runtime behavior snapshots before artifact read path exists.

Implementation:

1. Run baseline scenarios with current tip:
   - `runtimes/ruby/examples/assistant.rb` (Google News + Yahoo News flow)
   - `runtimes/ruby/examples/philosophy_debate.rb`
2. Extract correlated JSONL traces from `~/.local/state/recurgent/recurgent.jsonl`.
3. Store fixtures under `docs/baselines/<YYYY-MM-DD>/`:
   - `assistant-google-yahoo.jsonl`
   - `philosophy-debate.jsonl`
   - `README.md` with exact commands, model, and timestamp.
4. Reference these fixtures in acceptance tests as before/after evidence.

Exit criteria:

1. Baseline fixtures committed and indexed in docs.
2. Re-run process documented so future prompt/runtime changes can refresh baselines.

### Phase 0: Foundations and Contracts

Goals:

1. Define on-disk schema contracts.
2. Introduce prompt/runtime version constants.
3. Keep the runtime surface minimal and always-on for persistence.

Implementation:

1. Add runtime constants:
   - `TOOLSTORE_SCHEMA_VERSION`
   - `PROMPT_VERSION`
   - `MAX_REPAIRS_BEFORE_REGEN`
   - `KNOWN_TOOLS_PROMPT_LIMIT`
2. Add runtime configuration:
   - `toolstore_root` (storage location override)
3. Define JSON schema docs for:
   - `tools/registry.json`
   - `tools/<role>/<method>.json`

Exit criteria:

1. Constants and runtime configuration wired and documented.
2. Schema docs and validation stubs committed.

### Phase 1: Registry Persistence (Contracts Across Sessions)

Goals:

1. Persist delegated tool contracts to disk.
2. Load registry on startup.
3. Hydrate `<known_tools>` from disk-backed registry.

Implementation:

1. Add `ToolStore` module:
   - `load_registry`
   - `save_registry`
   - `upsert_tool_contract`
   - `find_tool_metadata`
2. Integrate `delegate(...)` and `tool(...)`:
   - write-through updates to registry file.
3. Startup load path:
   - initialize `@context[:tools]` from registry.
4. Add corruption handling:
   - invalid JSON -> quarantine file and continue with empty registry.

Suggested files:

1. `runtimes/ruby/lib/recurgent/tool_store.rb`
2. `runtimes/ruby/lib/recurgent/tool_store_paths.rb`
3. `runtimes/ruby/lib/recurgent.rb` (init/load + delegate hooks)
4. `runtimes/ruby/lib/recurgent/prompting.rb` (known-tool rendering already present; ensure disk-backed source)

Exit criteria:

1. New process startup sees previously delegated tools.
2. `tool("name")` works after restart without re-forging.

### Phase 2: Artifact Persistence (Write Path)

Goals:

1. Persist successful generated programs as method artifacts.
2. Capture execution metadata for fitness scoring.

Implementation:

1. On successful execution, persist artifact:
   - identity: `role + method_name`
   - payload: code, dependencies, metadata.
2. Track metrics:
   - success/failure counts
   - intrinsic/extrinsic/adaptive counts
   - last failure reason/class.
3. Persist both generated and repaired artifact generations.
4. Keep generation history:
   - latest + previous 2 artifacts per method.
5. Persist artifact updates with atomic write (temp + rename).

Suggested files:

1. `runtimes/ruby/lib/recurgent/artifact_store.rb`
2. `runtimes/ruby/lib/recurgent/artifact_metrics.rb`
3. `runtimes/ruby/lib/recurgent/call_execution.rb` (write-through hook)

Exit criteria:

1. Method artifact files are created/updated after successful calls.
2. Metadata fields present and valid.

### Phase 3: Artifact Read + Selection

Goals:

1. Use persisted artifacts before calling the provider.
2. Enforce selection policy using health/staleness signals.

Implementation:

1. Read-path before generation:
   - load artifact by `role + method_name`.
2. Selection policy:
   - missing/corrupt/runtime-incompatible -> regenerate.
   - contract fingerprint mismatch -> stale (repair/regenerate path).
   - healthy -> execute persisted.
   - degraded -> repair first if enabled.
3. Add compatibility checks:
   - schema version
   - runtime version
   - code checksum integrity.
4. Add `program_source` tracking:
   - `persisted | generated`.

Suggested files:

1. `runtimes/ruby/lib/recurgent/artifact_selector.rb`
2. `runtimes/ruby/lib/recurgent.rb` (`_generate_and_execute` orchestration)
3. `runtimes/ruby/lib/recurgent/observability.rb` (source fields)

Exit criteria:

1. Warm method calls execute from persisted artifacts with no provider call.
2. Incompatible artifacts bypass cleanly to generation path.

### Phase 4: Repair Flow and Failure Classification

Goals:

1. Repair failed persisted artifacts before full regeneration.
2. Bound repair chains with budget.
3. Separate intrinsic vs extrinsic vs adaptive failures for fitness decisions.

Implementation:

1. Failure classifier:
   - intrinsic examples: syntax error, parse error, logic mismatch, arity mismatch.
   - extrinsic examples: timeout, DNS/network failure, rate limit, remote 5xx.
   - adaptive examples: upstream schema/format drift, API response contract drift, parser assumptions invalidated by source changes.
2. Repair pipeline:
   - input includes failed code + error + contract + args signature.
   - validate repaired code via existing syntax gate.
   - promote on success.
3. Repair budget:
   - increment `repair_count_since_regen`.
   - if budget exhausted, force full regeneration on next failure.
4. Classification policy:
   - intrinsic: counts toward regeneration thresholds.
   - adaptive: route to repair first and count separately.
   - extrinsic: log for observability but do not penalize artifact health.
5. Add `program_source: repaired` and repair observability.

Suggested files:

1. `runtimes/ruby/lib/recurgent/artifact_repair.rb`
2. `runtimes/ruby/lib/recurgent/failure_classifier.rb`
3. `runtimes/ruby/lib/recurgent.rb` retry/generation orchestration

Exit criteria:

1. Persisted artifact failures trigger repair path deterministically.
2. Budget exhaustion triggers full regeneration.
3. Extrinsic failure spikes do not demote healthy artifacts.

### Phase 5: Prompt-Budget Lifecycle and Pruning

Goals:

1. Keep prompt injection bounded as tool catalog grows.
2. Support lifecycle management of stale tools/artifacts.

Implementation:

1. Ranking service for `<known_tools>`:
   - default utility score: `success_rate * recency_decay`.
   - bounded to `KNOWN_TOOLS_PROMPT_LIMIT`.
2. Pruning/archival policy:
   - soft de-prioritize first.
   - optional hard prune after retention window.
3. Add maintenance command:
   - list stale tools
   - prune/archive candidates
   - dry-run mode.

Suggested files:

1. `runtimes/ruby/lib/recurgent/known_tool_ranker.rb`
2. `runtimes/ruby/lib/recurgent/tool_maintenance.rb`
3. `bin/recurgent-tools` (optional CLI helper)

Exit criteria:

1. Prompt size remains bounded with large registry.
2. Maintenance operations are auditable and reversible.

## Data Model (v1)

### Registry (`tools/registry.json`)

```json
{
  "schema_version": 1,
  "tools": {
    "web_fetcher": {
      "role": "web_fetcher",
      "purpose": "fetch and parse web content from URLs, including RSS feeds",
      "deliverable": { "type": "object", "required": ["status", "content"] },
      "acceptance": [{ "assert": "status indicates success or failure" }],
      "failure_policy": { "on_error": "return_error" },
      "created_at": "2026-02-15T00:00:00Z",
      "last_used_at": "2026-02-15T00:00:00Z",
      "usage_count": 12
    }
  }
}
```

### Artifact (`tools/<role>/<method>.json`)

```json
{
  "schema_version": 1,
  "role": "web_fetcher",
  "method_name": "fetch",
  "contract_fingerprint": "sha256:...",
  "prompt_version": "2026-02-15.depth-aware.v3",
  "runtime_version": "0.1.0",
  "model": "claude-sonnet-4-5-20250929",
  "code_checksum": "sha256:...",
  "code": "result = ...",
  "dependencies": [],
  "success_count": 34,
  "failure_count": 3,
  "intrinsic_failure_count": 1,
  "adaptive_failure_count": 0,
  "extrinsic_failure_count": 2,
  "recent_failure_rate": 0.08,
  "last_failure_reason": "HTTP 503 upstream",
  "last_failure_class": "extrinsic",
  "repair_count_since_regen": 1,
  "created_at": "2026-02-15T00:00:00Z",
  "last_used_at": "2026-02-15T00:00:00Z",
  "last_repaired_at": "2026-02-15T00:00:00Z",
  "history": [
    { "id": "gen-3", "parent_id": "gen-2", "trigger": "repair:parse_error", "created_at": "..." },
    { "id": "gen-2", "parent_id": "gen-1", "trigger": "regenerate:budget_exhausted", "created_at": "..." },
    { "id": "gen-1", "parent_id": null, "trigger": "initial_forge", "created_at": "..." }
  ]
}
```

## Runtime Algorithm

For each dynamic call `(role, method_name)`:

1. Load candidate artifact by stable identity.
2. Validate integrity and compatibility.
3. Select path:
   - healthy -> execute persisted.
   - stale/degraded -> repair if enabled and budget available.
   - else regenerate.
4. Execute code in existing sandbox.
5. Classify failures (intrinsic/extrinsic/adaptive).
6. Update artifact metrics and lineage trigger:
   - intrinsic affects health score/regeneration threshold.
   - adaptive prioritizes repair flow.
   - extrinsic excluded from health demotion.
7. Persist updated artifact/registry state.
8. Emit observability fields.

## Testing Plan

### Unit Tests

1. ToolStore load/save and corruption quarantine.
2. Artifact serialization/validation/integrity checks.
3. Selector decision matrix (healthy/stale/degraded/corrupt).
4. Failure classifier intrinsic vs extrinsic vs adaptive mapping.
5. Repair budget enforcement.
6. Ranker and pruning policy logic.

### Integration Tests

1. Cross-session tool reuse:
   - forge tool in session A, use in session B.
2. Artifact warm path:
   - first call generates, second call skips provider.
3. Repair path:
   - persisted artifact fails, repair succeeds, no full regen.
4. Budget path:
   - repeated failures exceed repair budget -> forced regeneration.
5. Contract mismatch:
   - same method with changed contract fingerprint triggers stale handling.
6. Concurrent writers:
   - two sessions writing same `role + method_name` use atomic write semantics without partial/corrupt artifacts.

### Acceptance Tests

1. News workflow continuity across restarts.
2. Prompt refactor does not invalidate proven artifact.
3. Network outage does not permanently demote healthy fetcher.
4. Known-tools prompt remains bounded with 100+ tools.
5. Baseline-vs-post-persistence trace comparison demonstrates behavior preservation where expected.

## Observability Additions

Add to log entry schema:

1. `program_source`
2. `artifact_hit`
3. `artifact_prompt_version`
4. `artifact_contract_fingerprint`
5. `artifact_success_count`
6. `artifact_failure_count`
7. `artifact_intrinsic_failure_count`
8. `artifact_adaptive_failure_count`
9. `artifact_extrinsic_failure_count`
10. `artifact_generation_trigger`
11. `repair_attempted`
12. `repair_succeeded`
13. `failure_class`

## Rollout Controls and Safety

1. Start with artifact read disabled, write enabled.
2. Enable read path in canary mode (single role allowlist).
3. Enable repair path only after read-path stability.
4. Keep immediate kill switches:
   - disable artifact read
   - disable repair
   - force generation only.

Rollback plan:

1. Flip read/repair flags off.
2. Continue writing metrics for diagnostics.
3. Optionally archive suspect artifacts.

## Operational Playbook

1. Diagnose:
   - inspect recent `program_source` and failure class trends.
2. Quarantine:
   - disable specific role/method artifact.
3. Recover:
   - force regenerate and reset `repair_count_since_regen`.
4. Promote:
   - manually bless a validated artifact and optionally reset health counters (`--reset-metrics`).
5. Maintain:
   - periodic prune/archive based on recency.

## Dependencies and Sequencing

Prerequisites:

1. ADR 0012 accepted.
2. Existing prompting depth/known-tools mechanisms in place.
3. Existing tolerant `Outcome` and syntax validation path available.

Execution order:

1. Phase 0 -> Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5
2. No phase advances without prior exit criteria met.

## Acceptance Criteria

1. Tool contracts persist and reload across restarts.
2. Method artifacts execute from disk with deterministic selection.
3. Prompt changes do not force full artifact invalidation.
4. Repair budget prevents infinite patch chains.
5. Intrinsic/adaptive/extrinsic failure separation influences selection correctly.
6. Known-tools prompt remains bounded while registry grows.
7. Full plan covered by unit, integration, and acceptance tests.

## Implementation Defaults and Remaining Open Decisions

Defaults (adopt in this implementation):

1. Utility score starts simple:
   - `utility = success_rate * recency_decay`.
   - add exploration bonus only if telemetry shows new tools are starved.
2. Write strategy defaults to immediate atomic writes:
   - write temp file then rename for artifact/registry commits.
3. Artifact history defaults to embedded entries in each method JSON:
   - keep latest 3 generations with `id`, `parent_id`, `trigger`, and timestamp.

Remaining open decisions:

1. Maintenance command placement:
   - extend `bin/recurgent-watch` vs dedicated `bin/recurgent-tools` CLI.
