# Tool Self-Awareness and Boundary Referral Implementation Plan

## Objective

Implement ADR 0015 so Tools can emit referral-grade signals (`wrong_tool_boundary`, `low_utility`), while the runtime separates fast inline correction from slower out-of-band evolution.

This plan keeps architecture aligned with project tenets:

1. Agent-first mental model.
2. Tolerant interfaces by default.
3. Runtime ergonomics and clarity before premature constraints.
4. Ubiquitous language aligned to Tool Builder / Tool / Worker cognition.

## Scope

In scope:

1. Typed referral/usefulness outcomes (`wrong_tool_boundary`, `low_utility`).
2. Boundary referral metadata schema and normalization.
3. Inline correction lane behavior (deterministic hot path).
4. Out-of-band evolution lane (asynchronous evaluation and refinement signals).
5. Cohesion telemetry persistence and `<known_tools>` health injection.
6. `user_correction` capture as high-confidence utility ground truth.
7. Repair/evolution policy wiring across lanes.

Out of scope:

1. Runtime-autonomous tool decomposition or auto-splitting.
2. Hardcoded domain-specific scraping heuristics as architecture policy.
3. Lua runtime parity.

## Current State Snapshot

Already implemented:

1. Delegation contracts (`purpose`, `deliverable`, `acceptance`, `failure_policy`) flow through prompt and runtime.
2. Delegated outcome boundary shape validation (ADR 0014) with tolerant symbol/string key equivalence.
3. Tool persistence, artifact selection, and repair pipelines.
4. Method metadata in registry and prompt rendering support.

Current gaps:

1. Shape-valid but low-value outputs can still persist and look "successful".
2. A Tool cannot explicitly say "this request crosses my boundary" in typed form.
3. Failure signals do not yet distinguish implementation defects from boundary defects.
4. Out-of-band utility evaluation and redesign pressure are not formalized.

## Design Constraints

1. Runtime observes and reports; Tool Builder decides architecture.
2. Inline lane must stay cheap and deterministic.
3. Out-of-band lane may be richer and reflective, but must not block user calls.
4. Signals should be typed and inspectable in logs/artifacts.
5. Axis vocabulary is open in v1 with lightweight normalization from runtime.

## Delivery Strategy

Deliver in six phases. Each phase is independently testable.

### Phase 0: Taxonomy and Contracts

Goals:

1. Finalize typed outcome taxonomy for boundary/usefulness semantics.
2. Define metadata contract and normalization rules.
3. Establish baseline traces for before/after comparison.

Implementation:

1. Define outcome types:
   - `wrong_tool_boundary`
   - `low_utility`
2. Define referral metadata:
   - `boundary_axes` (array of strings)
   - `observed_task_shape` (string)
   - `suggested_split` (optional string)
   - `evidence` (optional string)
3. Define lightweight normalization for axes:
   - lowercase
   - trim whitespace
   - collapse obvious synonyms (for example `fetch`, `http`, `transport`)
4. Capture baseline traces:
   - movie-list conversation failure mode
   - repeated feed fetching (Google/Yahoo/NYT)

Exit criteria:

1. Outcome and metadata taxonomy documented.
2. Baseline fixtures captured under `docs/baselines/<date>/`.

### Phase 1: Inline Correction Lane (Hot Path)

Goals:

1. Enable Tools to emit typed referral/usefulness signals during active calls.
2. Keep hot path deterministic and low overhead.

Implementation:

1. Extend outcome taxonomy handling for `wrong_tool_boundary` and `low_utility`.
2. Add Tool-depth self-evaluation nudge scoped to open-world tasks (for example scraping/parsing/extraction), not deterministic math/string tasks.
3. Ensure inline behavior:
   - implementation crash -> typed execution error and repair path
   - boundary mismatch -> typed referral
   - low utility suspicion -> typed low utility signal
4. Preserve existing deliverable shape validation and tolerant key semantics.

Suggested files:

1. `runtimes/ruby/lib/recurgent/outcome.rb`
2. `runtimes/ruby/lib/recurgent/prompting.rb`
3. `runtimes/ruby/lib/recurgent/call_execution.rb`
4. `runtimes/ruby/lib/recurgent/call_state.rb`
5. `runtimes/ruby/lib/recurgent/observability.rb`

Exit criteria:

1. Tools can return `wrong_tool_boundary` and `low_utility` with metadata.
2. Inline call latency/flow remains stable (no out-of-band work in hot path).

### Phase 2: Telemetry Persistence and Cohesion Signals

Goals:

1. Persist boundary/usefulness signals in a form Tool Builder can consume.
2. Compute cohesion indicators from repeated failures across axes.

Implementation:

1. Extend artifact/registry metrics with:
   - boundary failure counts
   - low utility counts
   - normalized axis histograms
   - rolling cohesion warning
2. Record referral metadata in logs/artifacts.
3. Persist lightweight cohesion summaries per tool/method.

Suggested files:

1. `runtimes/ruby/lib/recurgent/artifact_metrics.rb`
2. `runtimes/ruby/lib/recurgent/artifact_store.rb`
3. `runtimes/ruby/lib/recurgent/tool_store.rb`
4. `runtimes/ruby/lib/recurgent/observability.rb`

Exit criteria:

1. Tool health includes boundary/usefulness telemetry.
2. Cohesion warnings can be derived from persisted state.

### Phase 3: `user_correction` Ground-Truth Capture

Goals:

1. Capture explicit user corrections as high-confidence utility labels.
2. Feed those labels into out-of-band evolution scoring.

Implementation:

1. Add `user_correction` event detection for top-level interactions.
2. Primary v1 signal (ship first): temporal same-topic re-ask detection:
   - same user/session trace,
   - repeated `ask` calls within short recency window,
   - same/near-identical capability pattern set (for example `http_fetch + html_extract`),
   - no intervening task-shape shift.
3. Store correction linkage to previous call/tool/method when trace context permits.
4. Weight `user_correction` higher than model self-assessment in utility scoring.

Secondary v1 signal (optional enrichment):

1. deterministic phrase heuristics (for example "this is wrong", "looks like a menu", "try again")
2. bounded, transparent matching rules with logs for calibration only

Suggested files:

1. `runtimes/ruby/lib/recurgent/call_execution.rb`
2. `runtimes/ruby/lib/recurgent/observability.rb`
3. `runtimes/ruby/lib/recurgent/pattern_memory_store.rb` (or dedicated telemetry store)

Exit criteria:

1. `user_correction` events are visible and queryable in telemetry.
2. Re-ask-based correction detection works without NLP dependency.
3. Utility scoring pipeline consumes correction events.

### Phase 4: `<known_tools>` Health Injection

Goals:

1. Surface actionable health/cohesion data to Tool Builder at decision time.
2. Keep prompt additions concise and bounded.

Implementation:

1. Extend `<known_tools>` metadata rendering with:
   - canonical methods
   - recent `wrong_tool_boundary` / `low_utility` counts
   - cohesion warning summary
2. Keep strict prompt budget caps and top-N ranking.
3. Ensure backward compatibility when health fields are absent.

Suggested files:

1. `runtimes/ruby/lib/recurgent/prompting.rb`
2. `runtimes/ruby/lib/recurgent/known_tool_ranker.rb`

Exit criteria:

1. Tool Builder prompts include health/cohesion evidence.
2. Prompt size remains bounded and stable.

### Phase 5: Out-of-Band Evolution Lane

Goals:

1. Run asynchronous reflective evaluation over accumulated telemetry.
2. Emit actionable evolution recommendations for Tool Builder.

Implementation:

1. Add out-of-band evaluator pass (CLI or scheduled command) that:
   - scores utility trends
   - detects repeated boundary referrals
   - identifies low-cohesion tools
2. Emit recommendations, not code mutations, for example:
   - tighten acceptance criteria
   - split a tool boundary
   - deprecate weak method alias
3. Feed recommendation summary into prompt-time health context.

Suggested files:

1. `runtimes/ruby/lib/recurgent/tool_maintenance.rb`
2. `bin/recurgent-tools` (new subcommand for evaluate/evolve)
3. `docs/observability.md` (operator workflow)

Exit criteria:

1. Out-of-band evaluator can produce recommendations from real traces.
2. Tool Builder receives recommendation signals without runtime-autonomous splitting.

### Phase 6: Policy Integration and Selection Pressure

Goals:

1. Integrate dual-lane policy into repair and artifact selection behavior.
2. Ensure low-value tools do not persist indefinitely.

Implementation:

1. Keep immediate implementation failures on repair path.
2. Treat repeated `low_utility` as adaptive failure in artifact health policy.
3. Route repeated `wrong_tool_boundary` to decomposition recommendation path.
4. Ensure boundary/usefulness failures influence regeneration priority over time.

Suggested files:

1. `runtimes/ruby/lib/recurgent/artifact_selector.rb`
2. `runtimes/ruby/lib/recurgent/artifact_repair.rb`
3. `runtimes/ruby/lib/recurgent/artifact_metrics.rb`

Exit criteria:

1. Selection policy demotes repeatedly low-utility artifacts.
2. Boundary referrals reliably contribute to decomposition pressure.

## Data Contract Updates (v1)

### Outcome Error Metadata

```json
{
  "error_type": "wrong_tool_boundary",
  "error_message": "Request crosses current tool boundary",
  "metadata": {
    "boundary_axes": ["transport", "extraction"],
    "observed_task_shape": "fetch + extract movie titles",
    "suggested_split": "separate HTTP transport from extraction",
    "evidence": "transport succeeded but extracted output remained low utility"
  }
}
```

### Tool Health Summary (Prompt/Registry)

```json
{
  "web_fetcher": {
    "methods": ["fetch_url", "fetch"],
    "health": {
      "wrong_tool_boundary_recent": 3,
      "low_utility_recent": 5,
      "cohesion_warning": true,
      "boundary_axes_top": ["transport", "extraction"]
    }
  }
}
```

## Test Strategy

### Unit Tests

1. Outcome creation/coercion for new typed errors and metadata.
2. Axis normalization and synonym collapsing.
3. Telemetry aggregation and cohesion warning calculations.
4. Prompt rendering with health blocks and budget limits.

### Integration Tests

1. Tool returns `wrong_tool_boundary` with metadata and caller receives typed outcome.
2. Repeated `low_utility` events alter artifact health classification.
3. `user_correction` events are captured and linked to prior low-utility paths.

### Acceptance Tests

1. Movie-list conversation:
   - low-quality scrape is flagged (`low_utility` or `wrong_tool_boundary`), not silent success drift.
2. Re-ask correction detection:
   - same-topic repeated ask within recency window emits `user_correction` deterministically.
3. Repeated boundary mismatch scenario:
   - out-of-band evaluator emits split recommendation.
4. Deterministic task scenario:
   - no unnecessary spirit-of-contract overhead in simple arithmetic/string transforms.

## Rollout and Operational Controls

1. Ship phases 1-2 first (typed signals + persistence) for observability confidence.
2. Enable phase 3 (`user_correction`) with deterministic re-ask detection first; add phrase heuristics only as optional enrichment after trace review.
3. Roll out phase 4 prompt injection with strict top-N and compact summaries.
4. Start phase 5 evaluator in dry-run/report-only mode before integrating phase 6 policy pressure.

## Risks and Mitigations

1. Risk: overuse of `wrong_tool_boundary` as escape hatch.
   - Mitigation: require evidence metadata and monitor referral rate by tool.
2. Risk: false-positive `user_correction` detection.
   - Mitigation: strict recency + capability-pattern match thresholds; trace review before enabling phrase enrichment.
3. Risk: prompt bloat from health injection.
   - Mitigation: bounded summaries and recency-weighted ranking.
4. Risk: overreactive decomposition pressure.
   - Mitigation: thresholding across repeated events and mixed evidence sources.

## Completion Checklist

1. [ ] Typed boundary/usefulness outcomes implemented and tested.
2. [ ] Axis normalization and referral metadata persisted.
3. [ ] `user_correction` telemetry captured and scored.
4. [ ] `<known_tools>` health/cohesion injection implemented with bounded prompt budget.
5. [ ] Out-of-band evaluator produces actionable recommendations.
6. [ ] Artifact policy integrates repeated `low_utility` as adaptive failure.
7. [ ] End-to-end acceptance traces demonstrate dual-lane behavior.
