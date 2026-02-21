# ADR 0026: Response Content Continuity Substrate

- Status: proposed
- Date: 2026-02-21

## Context

Recurgent currently provides three continuity layers:

1. state continuity (`context[...]`),
2. event continuity (`context[:conversation_history]` summary records),
3. executable continuity (persisted method/tool artifacts).

This leaves a known gap: continuity of response substance. A follow-up like "format that algorithm in markdown" often needs the prior response payload (text/code/object), not only call metadata.

Today, `conversation_history` is intentionally compact (ADR 0019 + ADR 0021): method, args, outcome summary, minimal provenance references. Full response payloads are not persisted there by default. This keeps context slim but prevents reliable content-level follow-up across turns.

This gap is not unique to assistant flows:

1. assistant follow-ups (reformat, summarize, compare prior answer),
2. debate/philosophy follow-ups (quote or refine prior argument text),
3. calculator or other roles when user asks to transform prior explanatory output.

The `content(ref)` helper is therefore a runtime retrieval primitive, not a shortcut memory hack. Generated code must still reason through follow-up intent:

1. identify a content-follow-up request,
2. locate the relevant history record,
3. resolve `content_ref`,
4. retrieve payload via `content(ref)`,
5. transform retrieved payload.

## Decision

Introduce a dedicated, bounded `Response Content Continuity` substrate as a fourth continuity layer.

Design rules:

1. Keep `context` as working memory, not archival content storage.
2. Keep `conversation_history` compact and metadata-first.
3. Store full response content in a separate bounded content store.
4. Link history records to content via stable `content_ref` identifiers.
5. Retrieve content on demand; do not preload full payloads into prompts.

### Current vs Post-ADR Shape

Current (metadata continuity only):

```ruby
# history record (simplified)
{
  call_id: "...",
  method_name: "ask",
  outcome_summary: { status: "ok", value_class: "Hash" }
}
```

Post-ADR (metadata + content reference):

```ruby
# history record (simplified)
{
  call_id: "...",
  method_name: "ask",
  outcome_summary: {
    status: "ok",
    value_class: "Hash",
    content_ref: "content:01J...",
    content_kind: "object",
    content_bytes: 1840,
    content_digest: "sha256:..."
  }
}
```

Content retrieval is explicit:

```ruby
entry = context[:conversation_history].last
ref = entry.dig(:outcome_summary, :content_ref)
content = content(ref) # bounded content-store lookup
result = format_as_markdown(content)
```

### Storage Model

Add a bounded runtime content store (session-scoped by default) with configurable retention:

1. max entries,
2. max bytes,
3. optional TTL,
4. LRU/oldest-first eviction.

Store only successful outcomes by default; configurable opt-in for selected error payload classes.

Stored content boundary (explicit):

1. Store body is the JSON-safe serialized snapshot of resolved `Outcome.value`.
2. Do not store the full `Outcome` envelope by default.
3. Preserve `outcome_summary` in history as compact metadata + reference (`content_ref`), not payload body.
4. If serialization fails, store a typed normalized fallback representation and mark serialization mode in metadata.

Depth-aware retention default:

1. depth `0`: store successful outcomes by default,
2. depth `>= 1`: store only when explicitly opted in or when parent orchestration references child content,
3. retention pressure should prioritize depth-0 continuity over internal child chatter.

### Prompt and Tooling Model

Prompt guidance should:

1. advertise `content_ref` semantics and helper availability,
2. teach explicit follow-up sequence: detect follow-up intent -> find relevant history record -> resolve `content_ref` -> evaluate `content_kind`/`content_bytes` -> call `content(ref)` when needed,
3. prefer summary-only responses when requested intent does not require full body retrieval,
4. avoid fabricating content when no reference exists.

### Boundary Model

`content_ref` is read-only from generated code.

1. generated code can fetch content by ref,
2. generated code cannot mutate existing content entries,
3. runtime owns creation/retention/eviction policy.

Retention policy governance:

1. runtime defaults are code-owned,
2. policy mutations (limits, TTL, eviction strategy) should flow through explicit proposal/authority lanes consistent with ADR 0025,
3. strict governance enforcement can be phased in during hardening (not required for initial substrate MVP).

## Status Quo Baseline

1. `conversation_history` stores compact summaries and does not persist full payloads by default.
2. Follow-up transforms that require prior payload content intermittently fail with "not found" style outcomes.
3. Some generated flows duplicate content ad hoc into `context`, causing inconsistent behavior and memory pressure.

## Expected Improvements

1. Content follow-up success rate (reformat/rewrite/summarize previous answer) improves from unstable baseline to `>= 95%` when prior turn produced storable content.
2. "No prior content found" false negatives drop by `>= 80%` in validated follow-up scenarios.
3. Prompt token pressure remains bounded because full content is not preloaded; only refs are embedded in history summaries.
4. Content-follow-up behavior becomes explainable in traces because ref resolution is explicit and observable.

## Non-Improvement Expectations

1. Existing state continuity semantics (`context[:value]`/role profile continuity) remain unchanged.
2. Artifact promotion/lifecycle policy (ADR 0023) remains unchanged.
3. Conversation-history record compactness goals from ADR 0019/0021 remain intact.
4. This ADR does not auto-promote content retention policy mutations without explicit governance.

## Validation Signals

1. Tests:
   - unit: content-store insert/retrieve/evict semantics,
   - integration: history record includes `content_ref` for successful outcomes,
   - acceptance: multi-turn follow-up transforms succeed using references.
2. Traces/logs:
   - `content_ref` presence in `outcome_summary`,
   - content-store hit/miss counters,
   - follow-up success/failure by intent class.
3. Thresholds:
   - follow-up content retrieval hit rate `>= 95%` for valid refs,
   - no unbounded growth: store obeys configured limits in stress tests.
4. Observation window:
   - minimum `>= 30` follow-up calls across `>= 3` sessions before final retention tuning.

## Rollback or Adjustment Triggers

1. If prompt/context size materially regresses (`>15%` median prompt growth), reduce inline ref payload and keep heavy details out of prompt.
2. If content-store misses remain high (`>10%`) for short-window follow-ups, adjust retention policy and ref selection heuristics.
3. If memory usage exceeds configured envelope under normal workload, tighten eviction policy and default limits.

## Scope

In scope:

1. bounded response content store,
2. history-to-content reference linkage,
3. runtime read helper for content retrieval,
4. prompt guidance and observability fields for content-ref flows.

Out of scope:

1. durable long-term archival/search system,
2. semantic embedding/vector retrieval,
3. autonomous summarization pipelines over all historical content.

## Consequences

### Positive

1. Enables reliable "work with what you just produced" follow-ups.
2. Preserves compact history design while adding payload retrievability.
3. Reduces ad hoc content copying into generic context keys.

### Tradeoffs

1. Adds a new storage subsystem and retention policy surface.
2. Requires careful eviction tuning for different roles/use patterns.
3. Adds new failure mode (`content_ref_not_found`) that must be handled explicitly.

## Alternatives Considered

1. Expand layer 1 (`context[:last_result]`/rolling payload memory).
   - Rejected: mixes working memory and archival payloads; poor boundedness semantics.
2. Expand layer 2 (store full payloads directly in `conversation_history`).
   - Rejected: history bloat for mostly-unused follow-up cases.
3. Reuse tool artifact store for response payloads.
   - Rejected: artifacts are executable-code lifecycle objects, not turn-content objects.

## Rollout Plan

1. Phase 0: schema and retention policy definition + baseline capture.
2. Phase 1: runtime content store + history reference linking.
3. Phase 2: prompt/runtime retrieval integration for follow-up flows.
4. Phase 3: observability, tuning, and policy hardening.

## Guardrails

1. Keep content continuity separate from state continuity and artifact continuity.
2. Never preload full content bodies into system/user prompts by default.
3. Enforce bounded retention with deterministic eviction.
4. Return typed `content_ref_not_found` (or `low_utility` where appropriate) instead of fabricated memory.

## Ubiquitous Language Additions

Add these terms to [`docs/ubiquitous-language.md`](../ubiquitous-language.md):

1. `Response Content Continuity`
2. `Content Store`
3. `Content Ref`
4. `Content Ref Resolution`
5. `Content Retention Policy`
6. `Content Eviction`
