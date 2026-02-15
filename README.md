# Recurgent

Inside-out LLM tool calling, organized as a multi-runtime monorepo.

Recurgent creates LLM-powered `Agent` objects that synthesize behavior at call time. You provide a role (`"calculator"`, `"file inspector"`, `"assistant"`), then call methods naturally; the model generates code, `Agent` executes it in object context, and logs each call.

Current status:

- `runtimes/ruby` is fully implemented.
- `runtimes/lua` is reserved for the upcoming Lua runtime.

## What This Is For

Recurgent is a runtime capability compiler for exploratory workflows:

- Instead of designing every tool, command, or skill API up front, you let the model design implementation at runtime.
- The main model can delegate work to `Agent` objects that synthesize their own behavior on demand.
- This is best for discovery, prototyping, and interactive automation where the solution surface is still evolving.

Practical framing:

- `Static tools/commands/skills` = fixed interfaces with deterministic behavior.
- `Agent` = model-designed interfaces and implementation at runtime.

Use a hybrid lifecycle:

1. Explore quickly with Agent.
2. Identify stable/high-value behavior.
3. Crystallize into explicit tools/commands for production reliability.

## Runtime Layout

```text
runtimes/
  ruby/   # production runtime, tests, examples
  lua/    # planned runtime
docs/     # shared architecture and product docs
```

## Quickstart

### Prerequisites

- `mise`
- Ruby (managed by `mise`, for `runtimes/ruby`)
- API key for at least one provider:
  - `ANTHROPIC_API_KEY` for Claude models
  - `OPENAI_API_KEY` for OpenAI models

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
ruby examples/calculator.rb
```

### Configure Runtime Before Tool Builder Calls

Configure dependency and source policy once before creating Tool Builders/Tools:

```ruby
Agent.configure_runtime(
  gem_sources: ["https://rubygems.org"], # default
  source_mode: "public_only",            # or "internal_only"
  allowed_gems: nil,                     # optional whitelist
  blocked_gems: nil                      # optional blacklist
)

tool_builder = Agent.for("research tool builder")
```

Optional asynchronous environment warmup:

```ruby
ticket = Agent.prepare(
  "pdf tool",
  dependencies: [{ name: "prawn", version: "~> 2.5" }]
)

prepared = ticket.await(timeout: 30)
tool = prepared.is_a?(Agent) ? prepared : nil
```

### Verify

```bash
cd runtimes/ruby
bundle exec rspec
bundle exec rubocop
bundle exec rake
```

## Documentation

- `docs/index.md` - documentation map and architecture overview
- `docs/onboarding.md` - collaborator onboarding and daily workflow
- `docs/idea-brief.md` - product vision and concept framing
- `docs/ubiquitous-language.md` - canonical Tool Builder/Tool vocabulary
- `docs/tolerant-delegation-interfaces.md` - canonical tolerant delegation guidance
- `docs/delegate-vs-for.md` - decision rules for `delegate(...)` vs `Agent.for(...)`
- `docs/delegation-contracts.md` - Tool Builder-authored Tool contract fields (`purpose`, `deliverable`, `acceptance`, `failure_policy`)
- `docs/observability.md` - runtime log schema and live watcher usage
- `docs/recurgent-implementation-plan.md` - implementation plan for LLM-native coordination surface and naming transition
- `docs/roadmap.md` - project roadmap
- `docs/governance.md` - maintainer governance model
- `docs/support.md` - support policy
- `docs/release-process.md` - release workflow and versioning
- `docs/open-source-release-checklist.md` - OSS launch readiness checklist
- `docs/adrs/` - architecture decision records
- `docs/maintenance.md` - dependency/runtime update policy and constraints
- `specs/contract/` - runtime-agnostic contract spec package for Ruby/Lua parity
- `runtimes/ruby/README.md` - Ruby runtime quick reference
- `runtimes/lua/README.md` - Lua runtime placeholder and planned contract

## Community and Policy

- `LICENSE` - project license (MIT)
- `CONTRIBUTING.md` - contribution policy and PR quality gates
- `CODE_OF_CONDUCT.md` - collaboration and anti-spam behavior policy
- `SECURITY.md` - vulnerability reporting process
- `SUPPORT.md` - support entrypoint

## Architecture Snapshot

```mermaid
flowchart LR
  U[User Code] --> M[method_missing]
  M --> P[Provider generate_code]
  P --> E[eval in object binding]
  E --> O[Outcome]
  E --> C[@context]
```

## FAQ

### Why `method_missing`?

It centralizes dynamic dispatch into one idiomatic Ruby hook, which keeps the core surface area small.

### Is this trying to replace tools and commands?

For exploratory work, yes: it can replace up-front tool design by letting the model synthesize capabilities at runtime.
For production paths, treat it as a discovery engine that should inform later explicit tool/command design.

### Where does state live?

Persistent runtime state lives in `@context` (a Hash) and is exposed to generated code as `context`.

### When should I use `delegate(...)` vs `Agent.for(...)`?

Use `Agent.for(...)` to bootstrap top-level agents.  
Use `delegate(...)` inside an active Tool Builder flow when summoning Tools so runtime contract stays aligned.

See `docs/delegate-vs-for.md` for concrete scenarios.

### Can Tool Builder shape Tool expectations explicitly?

Yes. Both `Agent.for(...)` and `delegate(...)` support contract fields:
`purpose`, `deliverable`, `acceptance`, and `failure_policy`.
If both a `delegation_contract` hash and field arguments are provided, field arguments win per key.
In Phase 1 these fields guide Tool prompting and are logged for observability; runtime enforcement is deferred.

### What do dynamic calls return?

Dynamic calls return `Agent::Outcome`.
- `status: :ok` carries `value`.
- `status: :error` carries typed error metadata (`error_type`, `error_message`, `retriable`).

### What does `respond_to?` mean for dynamic methods?

Setters (for example, `value=`) always return true, and context-backed readers return true once data exists. Unknown dynamic methods are not advertised via introspection even though `method_missing` can still handle them at runtime.

### Which models are supported?

Anthropic by default; OpenAI-compatible models are auto-routed by model prefix or explicit `provider:`.

### Can generated code use gems?

Yes. Generated programs can declare `dependencies`, and Recurgent materializes an environment for them.
Dependency-backed execution runs through worker isolation with a JSON boundary for args, context, and results.

### How are low-value bot PRs handled?

The repository enforces issue-first PR policy, required PR-template acknowledgements, and automated PR compliance checks.
Low-signal or non-compliant submissions may be closed without review per `CONTRIBUTING.md`.

### Where are call logs written?

Default JSONL path is `$XDG_STATE_HOME/recurgent/recurgent.jsonl` (or `~/.local/state/recurgent/recurgent.jsonl`).
Each entry includes `generation_attempt` so retries vs first-pass generations are measurable.

### How do I watch Agent behavior in real time?

Use `bin/recurgent-watch` to tail logs and inspect delegation trees, outcomes, retries, and errors live.
See `docs/observability.md`.

## Known Limitations

- Dependency-backed execution requires JSON-compatible args/context/results across worker boundaries.
- Provider responses can still be invalid at runtime (for example missing `code` in structured output).
- Tolerant outcome handling prevents hard crashes, but callers should validate artifact quality before treating results as final.

## Attribution

Copyright (c) 2026 Kulesh Shanmugasundaram.
Contributions are accepted under the repository `LICENSE` terms.
