# Tutorial: Personal Assistant (Progressive)

Audience: software engineers who want a practical, stepwise path from first call to governed, observable, profile-aware agent behavior.

This tutorial uses one evolving artifact: `runtimes/ruby/examples/assistant.rb`.

## Reading Modes

- Quick Path (15-25 min): run checkpoints only, observe behavior.
- Deep Path (60-120 min): apply each code change, inspect traces, and follow topic links.

## Prerequisites

1. Follow setup in `docs/onboarding.md`.
2. Work from `runtimes/ruby`.
3. Use isolated state roots during exercises to keep traces reproducible:

```bash
XDG_STATE_HOME=$PWD/../../tmp/tutorial-assistant/phase-0 bundle exec ruby examples/assistant.rb
```

## Copy/Paste Quickstart (10-15 min)

Run one complete loop (assistant + traces) before reading chapter details.

```bash
cd runtimes/ruby
ROOT="$PWD/../../tmp/tutorial-assistant/quickstart"
mkdir -p "$ROOT"

cat > "$ROOT/assistant_input.txt" <<'EOF'
What's the top news items in Google News, Yahoo! News, and NY Times
What's are the action adventure movies playing in theaters
What's a good recipe for Jaffna Kool
quit
EOF

XDG_STATE_HOME="$ROOT/xdg" bundle exec ruby examples/assistant.rb < "$ROOT/assistant_input.txt" | tee "$ROOT/assistant.out"
tail -n 8 "$ROOT/xdg/recurgent/recurgent.jsonl"
rg '"depth":0' "$ROOT/xdg/recurgent/recurgent.jsonl" | rg '"outcome_status":"error"'
```

What to verify:
1. all three prompts return usable responses,
2. top-level failures (if any) are visible in JSONL,
3. delegation/guardrail behavior is visible without changing code.

## Baseline Mental Model

- Top-level role is a Tool Builder (`Agent.for(...)`).
- Calls return `Agent::Outcome`.
- Delegations are tools created/reused through runtime policy.
- Runtime state and telemetry are first-class (toolstore + JSONL logs).

References:
- `docs/architecture.md`
- `docs/ubiquitous-language.md`
- `docs/delegate-vs-for.md`

## Recurgent Terms Used Here

These terms are domain-specific and appear throughout the chapters.

- `Tool Builder`: the top-level agent that owns user intent and synthesis.
- `Tool`: a delegated agent that executes a narrower capability boundary.
- `Delegate`: one Tool Builder action to materialize/invoke a Tool.
- `Outcome`: normalized return envelope (`ok?`, `value`, typed error fields).
- `Role Profile`: explicit role-level contract for sibling method coherence.
- `State Continuity Guard`: guardrail that enforces profile continuity expectations.
- `Shadow Mode`: evaluate and log policy/profile outcomes without blocking success.
- `Enforcement Mode`: policy/profile failures can block and trigger retries/typed errors.
- `Self Model`: captured awareness snapshot (`awareness_level`, authority, active versions).
- `Authority Boundary`: observe/propose is open; enact is explicitly gated.

Canonical reference:
- `docs/ubiquitous-language.md`

## Chapter Sequence

### Chapter 0: Minimal Assistant

Goal: run the assistant and understand the raw interaction loop.

File:
- `runtimes/ruby/examples/assistant.rb`

Code snippet:
```ruby
require_relative "../lib/recurgent"

assistant = Agent.for("personal assistant that remembers conversation history", model: Agent::DEFAULT_MODEL)

loop do
  print "> "
  input = $stdin.gets&.chomp
  break if input.nil? || %w[quit exit].include?(input.downcase)
  next if input.strip.empty?

  puts assistant.ask(input)
end
```

Run:
```bash
cd runtimes/ruby
XDG_STATE_HOME=$PWD/../../tmp/tutorial-assistant/phase-0 ruby examples/assistant.rb
```

Checkpoint:
1. prompt/response loop works,
2. `ask` returns structured outcomes (success or typed failure).

Deep links:
- `runtimes/ruby/README.md`
- `docs/onboarding.md`

### Chapter 1: Runtime Configuration

Goal: configure behavior intentionally before creating agents.

Add/modify:
1. `Agent.configure_runtime(...)` block in `assistant.rb`.
2. isolate state root for deterministic traces.

Code snippet:
```ruby
Agent.configure_runtime(
  role_profile_shadow_mode_enabled: true,
  role_profile_enforcement_enabled: true,
  promotion_shadow_mode_enabled: true,
  promotion_enforcement_enabled: false
)
```

Run:
```bash
cd runtimes/ruby
XDG_STATE_HOME=$PWD/../../tmp/tutorial-assistant/phase-1 ruby examples/assistant.rb
```

Checkpoint:
1. verify `recurgent.jsonl` is written under the phase-specific state root,
2. verify configured toggles (for example role-profile shadow/enforcement) are reflected in logs.

Deep links:
- `docs/runtime-configuration.md`
- `docs/observability.md`

### Chapter 2: Delegation with Explicit Contracts

Goal: make delegated behavior explicit and testable.

Exercise:
1. ask for multi-source news and observe delegation,
2. ensure delegated tools carry `purpose`, `deliverable`, `acceptance`, `failure_policy` where appropriate.

Code snippet (explicit delegation contract):
```ruby
news_tool = assistant.delegate(
  "news_aggregator",
  purpose: "fetch top headlines from multiple sources",
  deliverable: { type: "object", required: %w[headlines provenance] },
  acceptance: [{ assert: "headlines contains concrete items" }],
  failure_policy: { on_error: "return_error" }
)

news = news_tool.get_headlines(sources: %w[google yahoo nytimes])
puts news.ok? ? news.value : "#{news.error_type}: #{news.error_message}"
```

Checkpoint:
1. delegated calls appear in logs (`depth > 0`),
2. top-level assistant remains concise while child tools execute concrete capability work.

Deep links:
- `docs/specs/delegation-contracts.md`
- `docs/tolerant-delegation-interfaces.md`
- `docs/delegate-vs-for.md`

### Chapter 3: External Data + Provenance

Goal: enforce source-aware success semantics on external data.

Exercise:
1. run a news query,
2. inspect returned payload for provenance envelope,
3. inspect logs for guardrail behavior if provenance is missing.

Code snippet (expected success shape):
```ruby
{
  headlines: [...],
  provenance: {
    sources: [
      {
        uri: "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en",
        fetched_at: "2026-02-20T03:54:48Z",
        retrieval_tool: "news_aggregator",
        retrieval_mode: "live"
      }
    ]
  }
}
```

Checkpoint:
1. successful external-data outcomes include provenance sources,
2. provenance violations surface as typed failures/guardrail retries.

Deep links:
- `docs/adrs/0021-external-data-provenance-invariant.md`
- `docs/observability.md`

### Chapter 4: Add Role Profile Constraints

Goal: move from implicit conventions to explicit continuity contracts.

Use profile style already present in `assistant.rb`:
1. `kind: :shared_state_slot`
2. `scope: :all_methods`
3. `mode: :prescriptive`
4. `canonical_key: :conversation_history`

Code snippet:
```ruby
ASSISTANT_ROLE_PROFILE = {
  role: "personal assistant that remembers conversation history",
  version: 1,
  constraints: {
    conversation_history_slot: {
      kind: :shared_state_slot,
      scope: :all_methods,
      mode: :prescriptive,
      canonical_key: :conversation_history
    }
  }
}.freeze

assistant = Agent.for(
  "personal assistant that remembers conversation history",
  model: Agent::DEFAULT_MODEL,
  role_profile: ASSISTANT_ROLE_PROFILE
)
```

Checkpoint:
1. profile version appears in call telemetry,
2. continuity drift triggers typed violations when enforcement is on.

Deep links:
- `docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md`
- `docs/ubiquitous-language.md`

### Chapter 5: Observability and Diagnosis

Goal: read traces as an engineering feedback loop, not just logs.

Exercise:
1. run three prompts:
   - top news from Google News, Yahoo, NYT,
   - action-adventure movies in theaters,
   - Jaffna Kool recipe.
2. inspect log for:
   - top-level outcome status by request,
   - delegated calls and durations,
   - guardrail retries and latest failure class,
   - role-profile compliance fields.

Code snippets (local trace exploration):
```bash
# 1) Quick tail
tail -n 5 "$XDG_STATE_HOME/recurgent/recurgent.jsonl"

# 2) Find top-level failures quickly
rg '"depth":0' "$XDG_STATE_HOME/recurgent/recurgent.jsonl" | rg '"outcome_status":"error"'
```

```bash
# 3) Structured summary by role + status
ruby -rjson -e '
path = ARGV[0]
entries = File.readlines(path, chomp: true).map { |l| JSON.parse(l) }
puts entries.group_by { |e| e["role"] }.transform_values { |xs|
  xs.group_by { |e| e["outcome_status"] }.transform_values(&:count)
}
' "$XDG_STATE_HOME/recurgent/recurgent.jsonl"
```

Using Codex/Claude for log forensics:
1. Give the assistant a concrete log path and intent.
2. Ask for deterministic tables first, then interpretation.
3. Ask for file/line-linked remediation suggestions.

Prompt templates:
```text
Read this JSONL trace file: <absolute-path>.
1) Produce a table of top-level calls (timestamp, role, method, status, error_type, duration_ms).
2) Explain each error in plain engineering terms.
3) Propose the smallest code or config change to fix each, with file references.
```

```text
Compare these two trace files: <baseline-path> and <current-path>.
Show what improved, what regressed, and what remained unchanged.
Then propose one targeted experiment to validate each suspected cause.
```

Checkpoint:
1. you can explain exactly why each request succeeded/failed,
2. you can separate capability gaps from continuity/guardrail issues.

Deep links:
- `docs/observability.md`
- `docs/reports/adr-0024-scope-hardcut-validation-report.md`

### Chapter 6: Awareness vs Authority

Goal: allow proposal generation without uncontrolled runtime mutation.

Exercise:
1. inspect `self_model`/awareness fields in logs,
2. test proposal flows where apply requires maintainer authority.

Code snippet:
```ruby
Agent.configure_runtime(
  authority_enforcement_enabled: true,
  authority_maintainers: %w[kulesh]
)

planner = Agent.for("planner")
proposal = planner.propose(
  proposal_type: "role_profile_update",
  target: { role: "personal assistant that remembers conversation history", version: 2 },
  proposed_diff_summary: "tighten conversation history continuity checks"
)
# apply_proposal(...) requires maintainer-authorized actor under enforcement
```

Checkpoint:
1. observe/propose remains available,
2. enact is gated by explicit authority settings and actor identity.

Deep links:
- `docs/adrs/0025-awareness-substrate-and-authority-boundary.md`
- `docs/runtime-configuration.md`

### Chapter 7: Production Readiness Pass

Goal: convert example behavior into repeatable delivery quality.

Checklist:
1. local gates: `bundle exec rubocop`, `bundle exec rspec`,
2. deterministic validation script for the three canonical prompts,
3. trace review and issue creation for failures/regressions,
4. PR with linked issue + verification evidence.

Code snippet (minimal validation harness):
```bash
#!/usr/bin/env bash
set -euo pipefail

cd runtimes/ruby
ROOT="$PWD/../../tmp/tutorial-assistant/prod-check"
mkdir -p "$ROOT"

mise exec -- env XDG_STATE_HOME="$ROOT/xdg" bundle exec rubocop
mise exec -- env XDG_STATE_HOME="$ROOT/xdg" bundle exec rspec
mise exec -- env XDG_STATE_HOME="$ROOT/xdg" ruby examples/assistant.rb < "$ROOT/assistant_input.txt"
```

Deep links:
- `docs/open-source-release-checklist.md`
- `docs/maintenance.md`
- `docs/governance.md`

## Suggested Exercise Loop per Chapter

1. Run baseline chapter command.
2. Apply the chapter change.
3. Re-run with a fresh `XDG_STATE_HOME`.
4. Capture:
   - command output,
   - JSONL trace summary,
   - one-paragraph diagnosis (what improved / what regressed).

## Common Pitfalls

1. Mixing old/new state roots while comparing results.
2. Enabling strict enforcement before enough shadow observations.
3. Treating reliability metrics as semantic correctness guarantees.
4. Adding role constraints that over-prescribe before coordination evidence.

## Next Tutorial Candidates

1. Debate moderator (multi-role coordination and structured outcomes).
2. Tool promotion lifecycle (candidate -> probation -> durable -> degraded).
3. Proposal-driven role-profile evolution with maintainer approval.
