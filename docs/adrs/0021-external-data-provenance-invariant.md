# ADR 0021: External-Data Provenance Invariant

- Status: accepted
- Date: 2026-02-16

## Context

Recent traces exposed a repeatable trust failure pattern across domains (movies, news, and any external-data task):

1. Tools can return `Outcome.ok` without evidencing where data came from.
2. Follow-up questions like "what's the source?" cannot be answered deterministically from stored history.
3. Hardcoded fallback payloads can appear as successful outputs unless explicitly blocked.
4. Telemetry can overestimate reliability because "success" does not distinguish live retrieval vs fabricated/static fallback.

This conflicts with project tenets:

1. Agent-first mental model: Tool Builders and Tools need explicit, inspectable signals for quality and honesty.
2. Runtime ergonomics and clarity: users and tools should be able to trace output provenance directly.
3. Tolerant interfaces by default: provenance requirements must be generic and domain-agnostic, not movie-specific heuristics.
4. Ubiquitous language: "external-data success" should have one consistent meaning across all tools.

Related decisions:

1. ADR 0012 introduces persisted artifacts and health metrics.
2. ADR 0014 enforces outcome-boundary deliverable validation.
3. ADR 0017 keeps runtime observational for utility semantics (no hidden success->error coercion).
4. ADR 0016 defines validation-first retries for recoverable guardrails.
5. ADR 0019 makes conversation history structured and queryable.

## Decision

Adopt a global invariant: any successful outcome derived from external data MUST include provenance.

### 1. Provenance-Required Success for External Data

When code performs external retrieval/extraction behavior (HTTP fetch, remote feed parsing, file/network import), `Outcome.ok` must include provenance metadata.

If provenance is missing, generated code is invalid and must regenerate through the recoverable guardrail lane (ADR 0016), not silently pass.

### 2. Canonical Provenance Envelope

For external-data successes, the returned value should include a provenance envelope with stable fields:

1. `sources`: array of source entries
2. Each source entry includes:
   - `uri`
   - `fetched_at`
   - `retrieval_tool`
   - `retrieval_mode` (`live|cached|fixture`)
   - `content_fingerprint` (optional in v1; promoted to required once staleness telemetry depends on it)
3. Optional aggregation fields:
   - `extraction_tool`
   - `extracted_at`

Shape may be tolerant to symbol/string keys, but semantic fields above are required for contract-valid success.

### 3. Retrieval Mode Is First-Class

`retrieval_mode` is mandatory for external-data success and distinguishes:

1. `live`: content fetched during this call,
2. `cached`: content reused from prior fetch/storage,
3. `fixture`: deterministic test or fallback fixture data.

This makes data origin explicit at runtime and in telemetry.

Expected retrieval mode should be expressed in the existing contract surface, using acceptance assertions first:

1. Example: `{ assert: "retrieval_mode is live" }` for freshness-critical tasks (movie listings, breaking news),
2. Example: `{ assert: "retrieval_mode is cached or live" }` for reference/config use cases.

### 4. Guardrail, Not Runtime Semantic Coercion

Runtime does not rewrite domain semantics after execution (ADR 0017 remains intact).

Instead, runtime enforces provenance as a validation/guardrail invariant:

1. missing provenance on external-data `ok` => recoverable guardrail violation,
2. regeneration receives explicit correction feedback,
3. repeated failure exhausts retry budget with typed guardrail outcome.

Guardrail classification for "external-data behavior" is intentionally conservative in v1:

1. explicit `tool("web_fetcher")` / delegate-fetch patterns,
2. explicit stdlib HTTP/network signals (`require 'net/http'`, `Net::HTTP`, concrete `http(s)://` usage).

Runtime does not attempt broad semantic classification of arbitrary code in v1.

### 5. Conversation History Stores Provenance References

When appending conversation history records for external-data responses, store compact provenance references in `outcome_summary` so source questions are answerable later without bloating history context.

Default compact fields:

1. `source_count`,
2. `primary_uri`,
3. `retrieval_mode`.

Full source lists remain in trace/log artifacts, not per-turn conversation history records.

### 6. Telemetry and Health Use Provenance Signals

Observability and artifact health evaluation must treat provenance as reliability signal:

1. success without required provenance is invalid (guardrail failure),
2. repeated `fixture` use in production-like flows can trigger adaptive pressure,
3. stable `content_fingerprint` reuse across time can be analyzed for staleness.

## Scope

In scope:

1. global provenance invariant for external-data success,
2. canonical provenance field contract,
3. guardrail enforcement and retry feedback integration,
4. conversation-history provenance reference requirements,
5. telemetry hooks for provenance-aware reliability.

Out of scope:

1. domain-specific parser heuristics (movies/news/recipes),
2. adding browser-render or JS execution capabilities,
3. replacing existing outcome contract validator architecture.

## Consequences

### Positive

1. Source attribution becomes queryable fact, not narrative guess.
2. Hardcoded fallback `ok` paths are naturally suppressed.
3. Reliability metrics become more honest and comparable across tools.
4. External-data tools gain clear evolution pressure toward evidence-backed outputs.

### Tradeoffs

1. Contract/prompt complexity increases for external-data tools.
2. Some existing artifacts will fail guardrails until repaired.
3. Provenance propagation must be maintained across delegated tool chains.

## Alternatives Considered

1. Keep provenance optional and rely on prompt nudges.
   - Rejected: weak enforcement; repeated trust failures remain likely.
2. Coerce missing-provenance success to runtime error after execution.
   - Rejected: violates ADR 0017 observational semantics.
3. Domain-specific rules (for example only movies/news).
   - Rejected: does not generalize; fragments ubiquitous language.

## Rollout Plan

### Phase 1: Contract and Prompt Alignment

1. Add canonical provenance guidance to system/user prompts for external-data behaviors.
2. Add contract examples showing enforceable provenance requirements in `deliverable`/constraints.

### Phase 2: Guardrail Enforcement

1. Add recoverable guardrail check for external-data `Outcome.ok` without provenance.
2. Integrate correction hints into regeneration feedback.
3. Add regression tests for guardrail exhaustion and successful regeneration.

### Phase 3: History and Observability

1. Store compact provenance references in `conversation_history` outcome summaries.
2. Expose provenance fields in JSONL logs for trace inspection.

### Phase 4: Artifact Health Integration

1. Include provenance completeness and retrieval mode in adaptive scoring signals.
2. Add maintenance views for repeated fixture/cached-only behavior where live retrieval is expected.

## Guardrails

1. External-data success without provenance is invalid.
2. Provenance enforcement must run as validation/guardrail, not semantic post-processing rewrite.
3. Provenance keys remain tolerant (symbol/string), but required semantic fields are strict.
4. Delegated tools must preserve or enrich provenance; they must not drop provenance silently.

## Open Questions

1. When should `content_fingerprint` move from optional to required (telemetry threshold and migration criteria)?
2. Should retrieval-mode expectations remain acceptance-assert based in v1, or gain first-class deliverable constraint fields in v2?
