# Response Content Continuity Implementation Plan

- Status: draft
- Date: 2026-02-21
- Scope: ADR 0026 response content continuity substrate

## Objective

Implement a bounded response-content continuity layer so follow-up turns can reliably transform prior outputs without bloating working memory or conversation history.

Primary outcomes:

1. Prior response payloads are retrievable by stable `content_ref`.
2. `conversation_history` remains compact and metadata-first.
3. Follow-up intents that depend on prior content become deterministic.

## Status Quo Baseline

1. `conversation_history` stores compact summaries and minimal provenance references, not full response payloads.
2. Follow-up requests that require prior substance (reformat/rewrite/extract) can fail even when prior call succeeded.
3. Generated code sometimes duplicates payloads into ad hoc context keys, causing inconsistent behavior.

## Expected Improvements

1. Follow-up transform success for valid immediate prior content: from unstable baseline to `>= 95%`.
2. False negative "no prior content" outcomes: reduce by `>= 80%` in targeted scenarios.
3. Prompt growth impact from content continuity: keep median increase within `<= 5%` by using refs, not full payloads.

## Non-Improvement Expectations

1. State continuity (role profile key/shape enforcement) remains unchanged.
2. Tool/artifact lifecycle and promotion policy remain unchanged.
3. Existing external-data provenance compactness in history remains unchanged.

## Validation Signals and Thresholds

1. Tests:
   - content-store unit tests (insert, retrieve, evict, bounds),
   - history linkage tests (`content_ref` attached to successful outcomes),
   - acceptance tests for multi-turn content follow-up scenarios.
2. Traces/logs:
   - content-store write/read/eviction counters,
   - `content_ref` presence in `outcome_summary`,
   - follow-up success/failure with reason.
3. Thresholds:
   - ref resolution hit rate `>= 95%` for non-evicted refs,
   - boundedness invariant: store never exceeds configured max entries/bytes.
4. Observation window:
   - `>= 30` follow-up calls across `>= 3` sessions before retention tuning is finalized.

## Rollback or Adjustment Triggers

1. Prompt footprint regresses materially (`> 15%` median increase) -> slim prompt ref rendering.
2. Frequent `content_ref_not_found` within short-window follow-ups (`> 10%`) -> raise retention window and adjust eviction policy.
3. Memory/storage pressure beyond configured budget -> reduce defaults and tighten compaction.

## Non-Goals

1. No vector-search/embedding retrieval in this rollout.
2. No durable global archive across all sessions by default.
3. No automatic semantic summarization pipeline over all stored content.

## Design Constraints

1. Preserve separation of concerns:
   - state continuity (`context`) vs
   - event continuity (`conversation_history`) vs
   - executable continuity (artifact store) vs
   - response content continuity (new store).
2. Store is bounded and deterministic (no unbounded growth).
3. History references content by ID; history does not inline full payloads.
4. Typed failures for missing refs; never fabricate prior content.
5. Stored content body is JSON-safe serialized resolved `Outcome.value` by default, not full outcome envelope.
6. Depth-aware retention defaults apply: depth-0 store-on-success; depth>=1 store by opt-in or parent reference.

## Delivery Strategy

### Phase 0: Contract and Baseline

Goals:

1. Define content-store schema and retention policy contract.
2. Capture baseline follow-up failure modes.

Implementation:

1. Define `content_ref` format and `ContentStoreEntry` schema.
2. Define runtime config knobs: max entries, max bytes, optional TTL.
3. Freeze stored-payload boundary: JSON-safe serialized `Outcome.value` snapshot semantics, fallback serialization mode, metadata fields.
4. Define depth-aware retention policy contract for depth-0 vs depth>=1 calls.
5. Capture baseline traces for follow-up flows across assistant/calculator/debate.

Phase Improvement Contract:

1. Baseline snapshot: follow-up flows fail due to missing prior payload substance.
2. Expected delta: baseline evidence captured with reproducible scenarios.
3. Observed delta: to be recorded after phase validation.

Exit criteria:

1. Schema, payload boundary, and retention policy definitions accepted.
2. Baseline trace set stored and indexed.

### Phase 1: Bounded Content Store Runtime

Goals:

1. Add runtime-managed content store with deterministic bounds.
2. Attach `content_ref` metadata to successful call outcomes.

Implementation:

1. Implement `ContentStore` module/service (session-scoped default).
2. Store successful outcome payloads and compute digest/size metadata.
3. Add `content_ref`, `content_kind`, `content_bytes`, `content_digest` to history summary.
4. Enforce depth-aware write policy (default store depth-0; gated depth>=1 writes via explicit opt-in/parent reference).
5. Add config defaults and runtime configuration docs.

Phase Improvement Contract:

1. Baseline snapshot: no retrievable full response payload linked from history.
2. Expected delta: every eligible successful call has a resolvable `content_ref`.
3. Observed delta: to be recorded after phase validation.

Exit criteria:

1. Unit and integration tests for storage/linking are green.
2. Boundedness and eviction invariants verified.
3. Depth-aware retention behavior validated for assistant + debate-style nested flows.

### Phase 2: Retrieval Surface and Prompt Integration

Goals:

1. Enable generated code to retrieve stored content via refs.
2. Teach follow-up flows to resolve references before fallback behavior.

Implementation:

1. Add runtime helper for content resolution (read-only).
2. Update prompts with explicit reasoning sequence for content follow-ups:
   - detect follow-up intent,
   - identify candidate history record,
   - resolve `content_ref`,
   - use `content_kind`/`content_bytes` to decide summary-only vs full fetch,
   - fetch via `content(ref)` when required.
3. Add fallback policy for missing refs (`content_ref_not_found` / `low_utility`).
4. Add acceptance tests:
   - "format prior algorithm in markdown",
   - "summarize previous debate answer",
   - "rewrite previous explanation for beginners".

Phase Improvement Contract:

1. Baseline snapshot: follow-up transformations fail despite prior successful turn.
2. Expected delta: targeted follow-up transformations resolve and operate on prior payload content.
3. Observed delta: to be recorded after phase validation.

Exit criteria:

1. Acceptance scenarios pass consistently.
2. No prompt bloat beyond target threshold.
3. Follow-up traces show explicit ref-resolution chain instead of summary-only failure loops.

### Phase 3: Observability and Policy Hardening

Goals:

1. Add operational visibility and tune retention.
2. Harden behavior under stress and eviction boundaries.

Implementation:

1. Emit content continuity fields in logs and report docs.
2. Add counters: writes, hits, misses, evictions, expired refs.
3. Tune defaults using observation window evidence.
4. Integrate retention-policy mutations into ADR 0025 proposal/authority governance path.
5. Update docs with troubleshooting and expected failure semantics.

Phase Improvement Contract:

1. Baseline snapshot: no direct visibility into content-follow-up hit/miss dynamics.
2. Expected delta: measurable, tunable content continuity metrics available.
3. Observed delta: to be recorded after phase validation.

Exit criteria:

1. Metrics dashboards/reports show stable hit rate and bounded resource usage.
2. Governance path is exercised for at least one retention-policy adjustment proposal.
3. Documentation updated and linked in docs index.

## Test Strategy

1. Unit tests:
   - content entry normalization,
   - retention and eviction,
   - ref resolution behavior.
2. Integration tests:
   - history linkage,
   - prompt rendering with compact ref metadata,
   - runtime helper access control.
3. Acceptance tests:
   - assistant, calculator, debate content-follow-up scenarios.
4. Regression tests:
   - ensure no regressions in existing history/provenance semantics.

## Risks and Mitigations

1. Risk: store growth and memory pressure.
   - Mitigation: strict bounds, deterministic eviction, configurable defaults.
2. Risk: prompt bloat via excessive ref metadata.
   - Mitigation: keep prompt representation compact and bounded.
3. Risk: role-specific flows bypass new substrate.
   - Mitigation: acceptance coverage across assistant/debate/calculator.
4. Risk: stale refs after eviction create user confusion.
   - Mitigation: typed miss errors + concise repair guidance in prompts.
5. Risk: depth>=1 churn evicts useful top-level content.
   - Mitigation: depth-aware defaults + parent-reference selective retention.

## Completion Criteria

1. ADR 0026 acceptance criteria are met and evidenced.
2. Follow-up content transformations pass at target success rate in observation window.
3. Store boundedness and prompt-size constraints hold in stress tests.
4. Documentation and UL updates are merged and indexed.
