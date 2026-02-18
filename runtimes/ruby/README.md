# Recurgent Ruby Runtime

This directory contains the canonical Ruby implementation of Recurgent.

## Commands

```bash
bundle install
bundle exec rspec
bundle exec rubocop
bundle exec rake
./bin/recurgent
ruby examples/calculator.rb
ruby examples/debate.rb
```

## Structure

```text
lib/       # Agent runtime + providers + outcome model
spec/      # unit + acceptance tests
examples/  # executable demos
bin/       # executable entrypoint
```

## Dynamic Call Contract

Dynamic method calls return `Agent::Outcome`:

- `ok?` + `value` for successful calls
- `error?` + typed `error_type`/`error_message` for failures

## Runtime Configuration

Configure runtime dependency policy before creating Tool Builders:

```ruby
Agent.configure_runtime(
  gem_sources: ["https://rubygems.org"],
  source_mode: "public_only",
  allowed_gems: nil,
  blocked_gems: nil
)
```

To force internal source only:

```ruby
Agent.configure_runtime(
  gem_sources: ["https://artifactory.example.org/api/gems/ruby"],
  source_mode: "internal_only",
  allowed_gems: %w[nokogiri prawn]
)
```

## Async Preparation

Warm up dependency environments before first call:

```ruby
ticket = Agent.prepare(
  "pdf tool",
  dependencies: [{ name: "prawn", version: "~> 2.5" }]
)

result = ticket.await(timeout: 30)
```

`result` is:
- `Agent` when preparation succeeds
- `Agent::Outcome` when preparation fails (`error_type: "environment_preparing"`)

## Dependency Environment Invariants

- Environment cache identity includes Ruby version/platform, normalized dependency manifest, `source_mode`, and normalized `gem_sources`.
- Worker-vs-inline execution follows the tool's effective manifest:
  once a tool has a non-empty manifest, later calls with `dependencies: []` still execute in the worker-backed environment.
- Dependency manifests are monotonic per tool instance: existing gems/versions must remain identical, while new gems may be added.

## Contract Parity

Shared cross-runtime contract artifacts live at:

- `../../specs/contract/v1/agent-contract.md`
- `../../specs/contract/v1/scenarios.yaml`
