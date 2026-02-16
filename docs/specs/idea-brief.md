# Vision

## What this is

Inside-out LLM tool calling. Instead of humans designing API surfaces for LLMs to call, the human names a concept and the LLM designs the implementation. The LLM is both the caller and the toolsmith.

## LLM-shaped tools

Today's tool-use pattern: human designs API surface, LLM calls it. Agent inverts that: human names the concept, LLM designs the implementation. The object teaches itself how to be what you named it.

```ruby
f = Agent.for("file at /tmp/data.csv")
f.line_count
f.columns
f.rows_where("age > 30")
f.summary
```

You never define `rows_where` or `summary`. The LLM infers what those mean given the identity and generates code. The caller doesn't need to know the file format or what library to use.

Composition via chaining makes this recursive:

```ruby
db = Agent.for("database connection", deep: true)
users = db.find_inactive_users(days: 90)
users.export_to_csv("/tmp/inactive.csv")
```

## Security is external

The object shouldn't police itself. Process sandboxes, container isolation, and permission systems handle security. Baking restrictions into the system prompt makes the LLM worse at its job without providing real security. Don't restrict expressivity upfront.

## Caching and crystallization

Every method call currently regenerates code via an API round-trip. Caching eliminates this for repeated operations. Layered approach:

1. **Code cache** -- same method + similar context shape -> reuse generated code. First call pays LLM cost, subsequent calls are local eval.
2. **Method crystallization** -- after N cache hits, define a real Ruby method on the instance, bypassing method_missing entirely.
3. **Shared learning** -- cache across instances with the same identity. The second `Agent.for("calculator")` already knows how to `sum`.

The object starts as pure LLM improvisation and gradually solidifies into conventional code. The LLM becomes a compiler that runs once per novel interaction.

### Persistence layers

In-memory crystallization (`define_method`) is ephemeral — kill the process, everything evaporates. Full persistence requires layering:

1. **In-memory cache** — code strings keyed by (identity, method, context shape). Fast, gone on exit.
2. **Serialized code cache** — write cached code strings to disk (JSON/YAML). Next process boots, loads the cache, skips the LLM. Durable across restarts.
3. **Emitted source code** — dump crystallized methods as a real `.rb` file. Human-reviewable, version-controlled, loadable without recurgent at all.

The graduation path:

```
recurgent object (exploratory, every call hits LLM)
  → cached code strings (persistent across runs, eval from disk)
    → emitted .rb file (human-reviewable, git-tracked)
      → conventional Ruby class (no LLM dependency)
```

The LLM scaffolds the code, caching makes it durable, emission makes it independent. At the end, recurgent has removed itself from the picture.

## Related work: Recursive Language Models

[Recursive Language Models](https://alexzhang13.github.io/blog/2025/rlm/) (Zhang, 2025) share the same inversion of control. RLMs let the model decide _how_ to decompose a problem by writing code that recursively calls itself. Agent lets the model decide _what an object does_ by writing code that implements its methods. Both stop designing the strategy for the LLM and let it write the strategy as code.

|                | RLM                                       | Agent                              |
| -------------- | ----------------------------------------- | ------------------------------------- |
| Human provides | context + question                        | identity + method name                |
| LLM generates  | decomposition code (grep, chunk, recurse) | implementation code (eval in binding) |
| Key insight    | model chooses its own context strategy    | model chooses its own API surface     |
| Execution      | Python REPL                               | Ruby eval                             |

The crystallization idea maps here too -- RLMs that see the same decomposition pattern repeatedly could cache that strategy, just like an Agent object caching method implementations.

## Demos

### CSV Explorer (implemented)

A messy CSV with mixed date formats, missing values, and bad data. No CSV library, no date parser, no charting gem — just a name and a file path:

```ruby
csv = Agent.for("CSV data analyst for sales_2024.csv — messy dates, missing values")
csv.load
csv.total_revenue          # => 17404.8
csv.top_sellers(n: 3)      # figures out revenue per product, sorts, returns top 3
csv.revenue_by_quarter     # parses three date formats, computes quarter boundaries
csv.data_quality_report    # finds missing reps, N/A quantities, flagged notes
```

The LLM builds its own CSV parser, handles `2024-01-15` / `01/22/2024` / `Feb 14 2024`, skips "demo unit - not a real sale" rows, uses BigDecimal for money. Zero configuration.

Key observation: the return value shapes vary between runs (sometimes `total_qty`, sometimes `units_sold`). The demo script shouldn't assume internal structure — just print what comes back. This is a feature, not a bug: the object is conversational, not schematic. Crystallization would stabilize the shapes.

### Self-growing assistant (planned)

The crystallization story made tangible. An assistant that writes its own source code through use:

```ruby
assistant = Agent.for("Kulesh's personal assistant")
assistant.schedule_meeting("standup", "Monday 9am")
assistant.summarize_emails
assistant.draft_reply("re: Q3 planning", tone: "concise")
```

Each call generates code. The object learns what "schedule meeting" means for _you_. With caching and crystallization:

1. First `schedule_meeting` — LLM generates code, slow
2. Second `schedule_meeting` — cache hit, instant
3. After N hits — method crystallizes into a real Ruby method via `define_method`
4. Dump crystallized methods to a file — now you have a conventional Ruby class authored by behavioral specification

The bootstrap trick: use a second LLM to simulate usage patterns, pre-crystallizing common paths before a human ever touches it. The assistant arrives pre-trained on its own API.

The end state: objects that start as pure LLM improvisation and gradually solidify into conventional, fast, inspectable code. The LLM is a compiler that runs once per novel interaction, then gets out of the way.

## Language choice and the Lua option

Ruby is the right language to prove the concept: official SDKs from both Anthropic and OpenAI, rich developer tooling, `method_missing` collapses the dispatch into one clean hook. No plumbing required.

Lua is the better _theoretical_ host. `__index`/`__newindex` metamethods give the same dispatch control. `load()` with explicit environment tables is cleaner than Ruby's `eval` with `binding` — you choose exactly what generated code can see, no accidental leakage. The minimal stdlib forces the LLM to synthesize solutions from primitives rather than gluing libraries together, which aligns with the "LLM as toolsmith" vision.

The key insight: Lua was designed to be embedded. It runs inside C/C++ (game engines, Redis, nginx), Ruby (`rufus-lua`), Python (`lupa`), Go (`gopher-lua`), Rust (`mlua`), and the JVM (`LuaJ`). This opens an architecture where:

- Agent's core (dispatch, eval, caching) lives in Lua
- The host language (Ruby, Python, whatever) provides LLM SDK access
- Generated code runs in Lua's embedded runtime, which _is_ the sandbox

This addresses security-as-external-concern naturally — Lua's controlled environment provides isolation without restricting the host.

The tradeoff: Lua has no vendor LLM SDKs. You'd be writing HTTP clients against raw REST APIs. That's undifferentiated plumbing that ages badly. Ruby eliminates that friction today. Lua is the future bet on embeddability once the concept is proven.

## Latency

Latency will improve over time but not enough for hot paths. This is for exploratory, interactive, and tooling use cases -- not inner loops.
