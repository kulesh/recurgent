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

## Contract Parity

Shared cross-runtime contract artifacts live at:

- `../../specs/contract/v1/agent-contract.md`
- `../../specs/contract/v1/scenarios.yaml`
