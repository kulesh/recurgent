# Onboarding

## Environment Setup

```bash
mise install
cd runtimes/ruby
bundle install
```

Export provider keys as needed:

```bash
export ANTHROPIC_API_KEY=...
export OPENAI_API_KEY=...
```

## Runtime Configuration Before Solver Invocation

Configure runtime policy before creating a Solver:

```ruby
Agent.configure_runtime(
  gem_sources: ["https://rubygems.org"], # default
  source_mode: "public_only",            # "internal_only" supported
  allowed_gems: nil,                     # optional allowlist
  blocked_gems: nil                      # optional blocklist
)

solver = Agent.for("assistant solver")
```

Optional async prewarm for a known dependency-backed specialist:

```ruby
ticket = Agent.prepare(
  "pdf specialist",
  dependencies: [{ name: "prawn", version: "~> 2.5" }]
)

prepared = ticket.await(timeout: 30)
# prepared is Agent on success, or Agent::Outcome on failure
```

## Local Development Workflow

1. Recover workflow context:
```bash
bd onboard
bd prime
```
2. Pick work and claim it:
```bash
bd ready
bd update <issue-id> --status=in_progress
```
3. Implement with tests and lint gates:
```bash
cd runtimes/ruby
bundle exec rspec
bundle exec rubocop
bundle exec rake
```
4. Close and sync issue tracking:
```bash
bd close <issue-id>
bd sync --flush-only
```
5. Observe live runtime behavior when debugging delegation flows:
```bash
bin/recurgent-watch --status error
```

## Codebase Mental Model

- `Agent` intercepts unknown methods and delegates behavior synthesis to the configured provider.
- Providers return Ruby code via structured outputs.
- Generated code runs with access to `context`, `args`, `kwargs`, and `Agent`.
- Logging appends JSONL entries per LLM generation call.
- `trace_id`/`call_id`/`parent_call_id`/`depth` fields support delegation-tree analysis across runtimes.

## Quality Gates

- Unit/contract tests must pass.
- RuboCop must pass.
- Documentation must remain consistent with implementation and ADRs.

## Periodic Maintenance

```bash
cd runtimes/ruby
bundle update --all
bundle outdated
```

For constraint notes and upgrade order, see `docs/maintenance.md`.
