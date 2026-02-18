# Baseline Traces (2026-02-15)

Captured before cross-session artifact persistence implementation (ADR 0012) to establish pre-persistence behavior baselines.

## Environment

- Runtime: Ruby (`runtimes/ruby`)
- Model: `claude-sonnet-4-5-20250929`
- Log source: `~/.local/state/recurgent/recurgent.jsonl`

## Scenario 1: Personal Assistant (Google News + Yahoo News)

- Command:

```bash
cd runtimes/ruby
printf "What's the latest on Google News?\nWhat's the latest on Yahoo! News?\nexit\n" | bundle exec ruby examples/assistant.rb
```

- UTC window: `2026-02-15T04:55:03Z` to `2026-02-15T04:55:59Z`
- Console transcript: `docs/baselines/2026-02-15/assistant-session.txt`
- Extracted trace slice: `docs/baselines/2026-02-15/assistant-google-yahoo.jsonl`

## Scenario 2: Philosophy Debate

- Command:

```bash
cd runtimes/ruby
bundle exec ruby examples/philosophy_debate.rb
```

- UTC window: `2026-02-15T04:55:59Z` to `2026-02-15T04:56:29Z`
- Console transcript: `docs/baselines/2026-02-15/philosophy-debate-session.txt`
- Extracted trace slice: `docs/baselines/2026-02-15/philosophy-debate.jsonl`

## Notes

- Trace slices are extracted by line-offset windows from the append-only JSONL log.
- Trace slices in this directory are sanitized metadata fixtures (no raw fetched payloads, prompts, or generated code) so they are safe to redistribute.
- These files are intended for before/after comparison once artifact read/selection/repair paths are implemented.
