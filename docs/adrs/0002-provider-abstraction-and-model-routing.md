# ADR 0002: Provider Abstraction and Model Routing

- Status: accepted
- Date: 2026-02-13

## Context

Agent must support multiple LLM vendors while keeping core execution logic provider-agnostic.

## Decision

Introduce `Agent::Providers` with a single provider contract:

`generate_code(model:, system_prompt:, user_prompt:, tool_schema:) -> String`

Routing strategy:

- Default provider: Anthropic.
- Auto-route OpenAI-compatible models by prefix (`gpt-`, `o1-`, `o3-`, `o4-`, `chatgpt-`).
- Allow explicit `provider:` override.
- Lazily load provider gems only when instantiated.

## Consequences

- Positive: core logic stays stable while providers evolve independently.
- Positive: easier testability via provider doubles.
- Tradeoff: routing rules require periodic updates as model naming conventions change.
