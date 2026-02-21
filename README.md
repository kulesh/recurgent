# Recurgent

**An agent runtime that grows software through use.**

Recurgent doesn't produce code. It produces a tool-building organism that produces code. You give it a role and an environment. It discovers what tools it needs, builds them, and gets better over time.

#### A Calculator

```ruby
calc = Agent.for("calculator")

calc.memory = 5
calc.add(3)                                        # => 8
calc.multiply(4)                                   # => 32
calc.sqrt(144)                                     # => 12
calc.convert(100, from: "celsius", to: "fahrenheit") # => 212
calc.solve("2x + 5 = 17")                          # => x = 6
calc.history                                       # => [all of the above]
```

You didn't define `add`, `sqrt`, `convert`, or `solve`. There's no spec, no schema, no tool registration. The runtime synthesized behavior at call time, tracked state across calls, validated the results, and persisted stable implementations for reuse. Next time you call `calc.add`, it doesn't regenerate — it reuses what worked.

#### Personal Assistant with Conversation Memory

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

Conversation state persists across calls. Source follow-ups resolve from concrete references when available — when they're not, the agent returns an explicit unknown instead of fabricating provenance.

#### Agents That Spawn Other Agents

```ruby
debate = Agent.for("philosophy_symposium_host", verbose: true)

puts debate.host(
  question: "What is the good life?",
  thinkers: [
    "Stoic philosopher in the tradition of Marcus Aurelius",
    "Epicurean philosopher in the tradition of Epicurus",
    "Existentialist in the tradition of Simone de Beauvoir"
  ],
  rounds: 3
)

puts debate.debate_takeaways(10)
```

You defined a host and a question. Recurgent created three philosopher agents, gave each a contract (take a position, engage the others' claims), ran three rounds of structured debate where arguments sharpened against each other's actual responses, and synthesized takeaways. You didn't orchestrate any of that. The runtime figured out the delegation pattern, the turn structure, and the accumulation of conversational history on its own.

## What Happens Under the Hood

1. You call an `Agent` method naturally.
2. The runtime synthesizes behavior — code, contracts, even other agents.
3. Recurgent executes in a sandbox, validates outcomes, and logs traces.
4. Useful behavior is persisted and reused on future calls.
5. Failures trigger repair and evolution — not silent drift.

The output isn't a program. It's a living registry of capabilities, shaped by health metrics, contracts, failure histories, and evolutionary pressure. What works survives. What doesn't gets repaired or replaced.

### Agents That Build Their Own Tools

When you asked the personal assistant "What's the latest on Google News?", it needed to fetch web content. You didn't write a tool for that. The assistant did:

```ruby
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

The runtime decided it needed a specialized tool, wrote the contract (what it should accept, what it should return, how to handle failure), generated the implementation, and validated the results. The `web_fetcher` now exists in the registry — tested, typed, and available for reuse by any agent that needs it. Tools that meet their contracts survive. Tools that don't get repaired or replaced.

## Quickstart

### Prerequisites

- Ruby 3.4+
- Bundler
- One provider key:
  - `ANTHROPIC_API_KEY`, or
  - `OPENAI_API_KEY`

### Setup

```bash
cd runtimes/ruby
bundle install
```

### Run

```bash
cd runtimes/ruby
./bin/recurgent
ruby examples/assistant.rb
ruby examples/debate.rb
```

### Verify

```bash
cd runtimes/ruby
bundle exec rspec
bundle exec rubocop
```

## Where This Is Going

Recurgent is being built in public. Here's the arc:

**Now:** The Ruby runtime is actively developed and usable. Agents synthesize tools, persist what works, and evolve through use. This is the foundation.

**Next:** Recursim — a simulated environment where agents face synthetic scenarios designed to grow new capabilities and pressure-test existing ones. Think of it as a gym for agents: instead of waiting for real-world edge cases to surface organically, you manufacture them. The goal is to accelerate the evolutionary loop — building capabilities before users need them and finding gaps before users hit them.

**Ahead:** A Lua runtime for portability and embedding in constrained environments. The spec is runtime-agnostic by design — the contract and registry model should translate cleanly.

The long game is agents that don't just respond to instructions but develop genuine, persistent competence in their domain — shaped by real work, validated by contracts, and evolved through simulation. While you sleep, they exercise their capabilities, discover new ones, and get better at their job.

**Trajectory:** from single-agent emergence to measured, repeatable evolution loops.

## Known Limitations

- **Specialized interfaces still show up in some runs.** Agents occasionally create narrow methods (`fetch_google_news`) instead of reusable parameterized methods (`fetch_url(url)`), especially under weak contextual pressure. See [`docs/adrs/0023-solver-shape-and-reliability-gated-tool-evolution.md`](docs/adrs/0023-solver-shape-and-reliability-gated-tool-evolution.md) and [`docs/reports/adr-0023-phase-validation-report.md`](docs/reports/adr-0023-phase-validation-report.md).
- **Semantic correctness is still uneven for open-ended tasks.** Example: a call can return a structurally valid `Outcome.ok` for "action adventure movies in theaters" but still be low-utility or wrong for the user intent. Reliability gates improve stability, not truthfulness/utility semantics. See [`docs/adrs/0017-contract-driven-utility-failures-and-observational-runtime.md`](docs/adrs/0017-contract-driven-utility-failures-and-observational-runtime.md) and [`docs/reports/adr-0025-phase-validation-report.md`](docs/reports/adr-0025-phase-validation-report.md).
- **Role-profile continuity is opt-in.** Example: calculator siblings can drift (`memory=` writes `context[:memory]` while `add` reads `context[:value]`) unless a role profile is explicitly attached and enforced. See [`docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md`](docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md) and [`docs/plans/contract-first-role-profiles-state-continuity-implementation-plan.md`](docs/plans/contract-first-role-profiles-state-continuity-implementation-plan.md).
- **External-source workflows are brittle.** Example: a news flow may fetch live RSS/HTML successfully but parsing yields empty or malformed headline sets after upstream feed/layout changes. See [`docs/adrs/0021-external-data-provenance-invariant.md`](docs/adrs/0021-external-data-provenance-invariant.md), [`docs/observability.md`](docs/observability.md), and [`docs/reports/adr-0024-phase-validation-rollup.md`](docs/reports/adr-0024-phase-validation-rollup.md).
- **Content follow-up transforms are improving but not universal.** Example: after generating a long answer, a follow-up like "format that in markdown" can fail if the prior response content is not resolved from history/content refs. See [`docs/adrs/0026-response-content-continuity-substrate.md`](docs/adrs/0026-response-content-continuity-substrate.md) and [`docs/reports/adr-0026-phase-validation-report.md`](docs/reports/adr-0026-phase-validation-report.md).
- **Dependency-backed generated code paths are less battle-tested than stdlib-only paths.** Example: generated code can request dependencies that fail under local/bundler/runtime environment mismatch even when stdlib-only paths pass. See [`docs/adrs/0010-dependency-aware-generated-programs-and-environment-contract-v1.md`](docs/adrs/0010-dependency-aware-generated-programs-and-environment-contract-v1.md), [`docs/plans/dependency-environment-implementation-plan.md`](docs/plans/dependency-environment-implementation-plan.md), and [`docs/runtime-configuration.md`](docs/runtime-configuration.md).
- **Lua runtime parity is not implemented yet.** Example: runtime-agnostic specs exist, but `runtimes/lua` is still a placeholder while Ruby carries the active implementation. See [`docs/adrs/0006-monorepo-runtime-boundaries.md`](docs/adrs/0006-monorepo-runtime-boundaries.md), [`docs/roadmap.md`](docs/roadmap.md), and [`runtimes/lua/README.md`](runtimes/lua/README.md).

## Documentation Map

- [`docs/index.md`](docs/index.md) - full documentation index
- [`docs/architecture-onboarding.md`](docs/architecture-onboarding.md) - step-by-step architecture onboarding for contributors
- [`docs/architecture.md`](docs/architecture.md) - canonical architecture and lifecycle diagrams
- [`docs/observability.md`](docs/observability.md) - log schema, trace model, live watcher
- [`docs/adrs/README.md`](docs/adrs/README.md) - design decisions and rationale
- [`docs/plans/README.md`](docs/plans/README.md) - implementation plan map
- [`runtimes/ruby/README.md`](runtimes/ruby/README.md) - Ruby runtime quick reference

## References

- RLMs - https://alexzhang13.github.io/blog/2025/rlm/
- gremllm - https://github.com/awwaiid/gremllm
- Agentica - https://github.com/symbolica-ai/arcgentica
- SkillsBench: Benchmarking How Well Agent Skills Work Across Diverse Tasks - https://arxiv.org/abs/2602.12670

## Community and Policy

- [`CONTRIBUTING.md`](CONTRIBUTING.md)
- [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
- [`SECURITY.md`](SECURITY.md)
- [`LICENSE`](LICENSE)
