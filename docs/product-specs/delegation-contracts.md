# Delegation Contracts (Phase 1)

Phase 1 introduces Tool Builder-authored Tool contracts as expression-only metadata.

## API

Both `Agent.for(...)` and `delegate(...)` accept optional contract fields:

- `purpose`
- `deliverable`
- `acceptance`
- `failure_policy`

`delegate(...)` example:

```ruby
pdf_tool = tool_builder.delegate(
  "pdf tool",
  purpose: "produce a PDF artifact for downstream download",
  deliverable: { type: "object", required: %w[path mime bytes] },
  acceptance: [{ assert: "mime == 'application/pdf'" }, { assert: "bytes > 0" }],
  failure_policy: { on_error: "fallback", fallback_role: "archiver" }
)
```

`Agent.for(...)` example:

```ruby
pdf_tool = Agent.for(
  "pdf tool",
  purpose: "produce a PDF artifact for downstream download",
  deliverable: { type: "object", required: %w[path mime bytes] },
  acceptance: [{ assert: "mime == 'application/pdf'" }, { assert: "bytes > 0" }],
  failure_policy: { on_error: "fallback", fallback_role: "archiver" }
)
```

Merge rule:

1. `delegation_contract` hash only -> use hash.
2. field args only -> build contract from fields.
3. both -> merge, with field args winning per key.

## Behavior in Phase 1

1. Contract fields are injected into Tool prompts.
2. Contract fields are logged for traceability (`contract_purpose`, etc.) with `contract_source` (`none`, `hash`, `fields`, `merged`).
3. Runtime does not enforce validation yet.
4. Tool Builder remains responsible for evaluating Tool output quality.

Validation design is intentionally deferred to a later phase.

## Example References

- [`runtimes/ruby/examples/observability_demo.rb`](../../runtimes/ruby/examples/observability_demo.rb)
- [`runtimes/ruby/examples/debate.rb`](../../runtimes/ruby/examples/debate.rb)
- [`runtimes/ruby/examples/philosophy_debate.rb`](../../runtimes/ruby/examples/philosophy_debate.rb)
