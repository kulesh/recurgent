# Recurgent

Recurgent is an agent runtime for growing software through use.

## Mission

Build agents that:

1. Forge useful Tools from real work.
2. Reuse and evolve those Tools over time.
3. Stay honest at boundaries (typed outcomes, contracts, provenance).
4. Become more capable across sessions, not just within one chat.

This repository is the implementation of that mission, starting with the Ruby runtime.

## What Recurgent Does

At a high level:

1. You call an `Agent` method naturally.
2. The model generates Ruby code for that call.
3. Recurgent executes it in a sandbox, validates outcomes/contracts, and logs traces.
4. Useful tool behavior is persisted and reused on future calls.
5. Failures trigger repair/evolution lanes instead of silent drift.

Core posture:

- Agent-first mental model.
- Tolerant interfaces by default.
- Runtime ergonomics for introspection and evolution.
- Ubiquitous language aligned to model cognition (Tool Builder, Tool, Worker).

## Examples

### 1) Grow a Calculator (Self-contained system)

```ruby
calculator = Agent.for("calculator")

sum = calculator.add(2, 3)
fib = calculator.fibonacci(10)

puts sum.value # => 5
puts fib.value # => 55
```

You did not pre-define `add` or `fibonacci`. The runtime synthesizes behavior at call time and can persist stable implementations.

### 2) Personal Assistant with Source Follow-up (Interactive system)

```ruby
assistant = Agent.for(
  "personal assistant that remembers conversation history",
  log: "tmp/recurgent.jsonl",
  debug: true
)

news = assistant.ask("What's the latest on Google News?")
src  = assistant.ask("What's the source?")

puts news.value
puts src.value
```

Recurgent tracks structured conversation history. Source follow-ups are resolved from concrete source refs when present; when missing, the agent returns explicit unknown instead of fabricating provenance.

### 3) Forge and Reuse a Tool

```ruby
assistant = Agent.for("research assistant")

fetcher = assistant.delegate(
  "web_fetcher",
  purpose: "fetch content from HTTP/HTTPS URLs with redirect handling",
  deliverable: { type: "object", required: ["status", "body"] },
  acceptance: [{ assert: "status code is present and body is string" }],
  failure_policy: { on_error: "return_error" }
)

result = fetcher.fetch_url("https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en")
puts result.ok?
```

Delegation contracts define expectations; runtime validation enforces boundaries; outcomes are typed.

## Quickstart

### Prerequisites

- `mise`
- Ruby (managed via `mise`)
- One provider key:
  - `ANTHROPIC_API_KEY`, or
  - `OPENAI_API_KEY`

### Setup

```bash
mise install
cd runtimes/ruby
bundle install
```

### Run

```bash
cd runtimes/ruby
./bin/recurgent
ruby examples/assistant.rb
```

### Verify

```bash
cd runtimes/ruby
bundle exec rspec
bundle exec rubocop
```

## Repository Layout

```text
runtimes/
  ruby/   # active runtime implementation
  lua/    # reserved for parity work
docs/     # product, architecture, ADRs, implementation plans
specs/    # runtime-agnostic contract specs
```

## Documentation Map

Start here:

- `docs/index.md` - full documentation index
- `docs/architecture.md` - canonical architecture + flow diagrams
- `docs/ubiquitous-language.md` - core language and terms
- `docs/observability.md` - logs, traces, live watcher
- `docs/adrs/README.md` - architecture decisions and rationale
- `runtimes/ruby/README.md` - Ruby runtime quick reference

Key policies/specs:

- `docs/specs/delegation-contracts.md`
- `docs/tolerant-delegation-interfaces.md`
- `docs/delegate-vs-for.md`

## Project Status

- Ruby runtime: actively developed and used.
- Lua runtime: planned.
- Recursim: specified, implementation staged.

## Community and Policy

- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`
- `SECURITY.md`
- `LICENSE`

