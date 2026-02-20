# ADR 0026: Structured Output Provider Eligibility

- Status: accepted
- Date: 2026-02-20

## Context

Recurgent's core loop generates Ruby code by asking an LLM to fill a structured schema (a `code` field, optionally `dependencies`). The correctness of every downstream step — `GeneratedProgram.from_provider_payload!`, dependency resolution, sandbox eval — depends on the LLM response being valid JSON that conforms to the schema. If the provider only returns freeform text, we would need a parsing layer to extract code from prose, introducing a new and unpredictable failure mode at the most sensitive boundary in the system.

Two providers are supported today:

| Provider  | Structured output mechanism                        |
|-----------|----------------------------------------------------|
| Anthropic | `tool_use` with `tool_choice` (forced tool call)   |
| OpenAI    | Responses API with `json_schema` strict mode       |

Both guarantee well-formed JSON matching our schema at the API level. No parsing heuristics are involved.

The question is: what is the eligibility criterion for adding new providers (Gemini, GLM, Mistral, etc.)?

## Decision

**A provider is eligible if and only if its API offers a first-class structured output mechanism that guarantees valid JSON conforming to a caller-supplied schema.**

Concretely, the provider's SDK must support at least one of:

1. **Forced tool/function call** — the API guarantees a tool call response whose arguments match the declared schema (e.g., Anthropic `tool_choice: { type: "tool" }`).
2. **JSON schema mode** — the API constrains output to valid JSON matching a caller-supplied JSON Schema (e.g., OpenAI `text.format.type: "json_schema"` with `strict: true`).

Mechanisms that do **not** qualify:

- "JSON mode" without schema enforcement (output is valid JSON but shape is uncontrolled)
- Freeform text with markdown code fences
- Regex-constrained generation without full JSON Schema support
- System prompt instructions requesting JSON (compliance is probabilistic)

Each provider class implements exactly one interface method:

```ruby
generate_program(model:, system_prompt:, user_prompt:, tool_schema:, timeout_seconds: nil) → Hash
```

The returned `Hash` must be passable to `GeneratedProgram.from_provider_payload!` with no intermediate parsing, normalization, or extraction from prose.

## Status Quo Baseline

1. Two providers (Anthropic, OpenAI) both use first-class structured output. Zero freeform parsing paths exist.
2. `GeneratedProgram.from_provider_payload!` assumes its input is a Hash with string/symbol keys. No regex extraction, no markdown stripping.
3. Provider failure modes are limited to: network errors, rate limits, missing tool_use block, empty output. All are cleanly catchable.

## Expected Improvements

1. Provider count may grow, but the reliability contract at the provider boundary remains identical for every provider.
2. No new failure modes introduced at the structured output layer regardless of provider count.
3. Provider eligibility evaluation becomes a binary check rather than a judgment call.

## Non-Improvement Expectations

1. `GeneratedProgram.from_provider_payload!` remains unchanged — new providers must conform to it, not the other way around.
2. The `generate_program` interface signature remains unchanged.
3. Test patterns for providers remain structurally identical (mock SDK, assert schema enforcement, assert Hash output).

## Validation Signals

1. Tests: every provider spec asserts that `generate_program` returns a Hash directly consumable by `GeneratedProgram.from_provider_payload!`.
2. Code review: any new provider PR must demonstrate which API feature enforces schema conformance.
3. Threshold: zero regex/string-parsing operations between API response and `GeneratedProgram.from_provider_payload!` input.

## Rollback or Adjustment Triggers

1. If a provider's "structured output" feature silently produces malformed JSON at a rate > 1%, demote it to unsupported.
2. If a major model family lacks any structured output mechanism, document it as ineligible rather than building a parser.

## Scope

In scope:

1. Eligibility criteria for new providers.
2. The invariant that `generate_program` returns a Hash, not a String requiring extraction.
3. Documentation of currently supported and evaluated providers.

Out of scope:

1. Specific implementation of any new provider (those are separate PRs).
2. Model quality or capability evaluation beyond structured output support.

## Consequences

### Positive

1. The provider boundary stays zero-ambiguity: either the API guarantees the shape, or we don't use it.
2. `GeneratedProgram` and all downstream consumers never need defensive parsing.
3. New provider onboarding is mechanical: implement `generate_program`, point it at the SDK's structured output feature, write the same spec pattern.

### Tradeoffs

1. Some model families may be excluded despite strong generation quality, if their API lacks structured output.
2. Provider eligibility must be re-evaluated as APIs evolve (e.g., a provider adding schema-enforced JSON mode becomes eligible).

## Alternatives Considered

1. **Freeform text with regex extraction** — parse code from markdown fences or JSON from prose. Rejected: introduces a probabilistic failure mode at the most critical boundary.
2. **"JSON mode" without schema** — accept any valid JSON and validate shape ourselves. Rejected: shifts schema enforcement from the API (deterministic) to our code (error-prone for edge cases like extra fields, wrong types).
3. **Dual-path: structured where available, freeform fallback** — use structured output when the provider supports it, fall back to parsing otherwise. Rejected: two code paths means two failure profiles, and the fallback path would be undertested in production.

## Rollout Plan

Adding a new provider is a four-phase process. Each phase is a separate PR.

### Phase 1: Eligibility audit

Evaluate the candidate provider's API documentation for structured output support.
Document findings in a table:

| Provider | Structured output mechanism | Schema enforcement? | Eligible? |
|----------|----------------------------|---------------------|-----------|

Known candidates and current assessment:

| Provider | Mechanism | Eligible? | Notes |
|----------|-----------|-----------|-------|
| Anthropic | `tool_use` + `tool_choice` | Yes | Supported today |
| OpenAI | Responses API `json_schema` strict | Yes | Supported today |
| Google Gemini | `response_schema` with `response_mime_type: "application/json"` | Likely yes | Needs SDK evaluation (`google-gemini` gem) |
| Mistral | Function calling with `tool_choice: "any"` | Likely yes | Needs SDK evaluation |
| GLM (Zhipu) | Function calling | Unclear | Needs API documentation review |
| Ollama/local | Depends on model; some support structured output via `format: "json"` | Varies | No schema enforcement — likely ineligible unless JSON Schema mode is available |

### Phase 2: Provider implementation

For each eligible provider:

1. Add `Providers::<Name>` class in `providers.rb` implementing `generate_program`.
2. Add model prefix pattern (e.g., `GEMINI_MODEL_PATTERN = /\A(gemini-)/`).
3. Update `_build_provider` routing in `recurgent.rb`.
4. Lazy-require the SDK gem with `rescue LoadError` guidance.
5. Add the gem as an optional dependency in the gemspec (same pattern as `openai`).

### Phase 3: Test coverage

Mirror the existing provider spec pattern:

1. Mock the SDK client.
2. Assert `generate_program` returns a Hash.
3. Assert the structured output mechanism is invoked (schema passed to API).
4. Assert error on missing/malformed output.
5. Assert timeout behavior.

### Phase 4: Documentation

1. Update `providers.rb` module doc — add provider to the supported list.
2. Update `CLAUDE.md` — add provider to Dependencies section, document env var and model prefixes.
3. Update ADR 0002 — add new model prefix routing entry.

## Guardrails

1. `generate_program` must return a Hash. Any provider returning a String triggers an immediate error, not a parse attempt.
2. No `gsub`, `match`, `scan`, or regex operations may appear between a provider's API response and the Hash returned by `generate_program`.

## Ubiquitous Language Additions

1. **Structured output guarantee** — an API-level mechanism that ensures the LLM response is valid JSON conforming to a caller-supplied schema, with no parsing required by the caller.
2. **Provider eligibility** — the binary determination of whether a provider's API meets the structured output guarantee. Eligible or not; no partial credit.
