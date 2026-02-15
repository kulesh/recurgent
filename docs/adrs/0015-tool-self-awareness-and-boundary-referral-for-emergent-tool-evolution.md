# ADR 0015: Tool Self-Awareness and Boundary Referral for Emergent Tool Evolution

- Status: proposed
- Date: 2026-02-15

## Context

Recent live traces showed a recurring failure class:

1. A Tool can return structurally valid data (`Outcome.ok`) that is semantically low value for caller intent.
2. A Tool can be asked to perform work across capability boundaries it does not own (for example, HTTP transport plus extraction semantics).
3. Current runtime contract enforcement (ADR 0014) validates `deliverable` shape, but does not yet evaluate whether output satisfied the spirit of the contract.
4. The Tool Builder receives weak signals ("execution failed" or noisy successes) instead of clear decomposition signals.

The project tenets require:

1. Agent-first mental model.
2. Tolerant interfaces by default.
3. Runtime ergonomics and clarity before premature constraints.
4. Ubiquitous language aligned to Agent thinking.

In that language:

1. Tool Builders forge and compose Tools.
2. Tools execute and evolve themselves, or declare they are the wrong boundary.
3. Workers execute directly.

The missing primitive is referral semantics: a Tool that can say "this request crosses my capability boundary" in a typed, actionable way.

## Decision

Introduce first-class Tool boundary referral and cohesion telemetry, with a dual-lane evolution model:

1. inline correction lane for immediate call safety and truthful outcomes;
2. out-of-band evolution lane for contract/tool boundary refinement over time.

### 1. Add Typed Boundary/Usefulness Outcomes

Add canonical typed outcomes for Tool self-evaluation:

1. `wrong_tool_boundary`
   - Meaning: the Tool can execute part of the request, but the requested outcome crosses capability boundaries it should not own.
2. `low_utility`
   - Meaning: output is structurally valid but semantically weak for caller intent.

These are not crashes; they are referrals with intent metadata.

### 2. Standardize Boundary Referral Metadata

When returning `wrong_tool_boundary`, include metadata fields:

1. `boundary_axes` (for example: `["transport", "extraction"]`)
2. `observed_task_shape`
3. `suggested_split` (optional concise suggestion)
4. `evidence` (optional short explanation)

This preserves tolerant interfaces while making boundary mismatch machine-actionable.

### 3. Add Tool Self-Evaluation Protocol (Tool Depth)

For Tool-depth execution prompts, add a self-evaluation nudge:

1. Did I satisfy the letter of `deliverable`?
2. Did I satisfy the spirit/usefulness of caller intent?
3. If not, should I return typed referral (`wrong_tool_boundary`) instead of low-quality success?

This is guidance, not hard prohibition.

### 4. Persist Tool Health and Cohesion Telemetry

Persist per tool/method telemetry signals:

1. failure signatures and counts (`execution`, `contract_violation`, `wrong_tool_boundary`, `low_utility`, etc.)
2. repair attempts and outcomes
3. boundary-axis clustering statistics
4. rolling cohesion warning signal when failures cluster across distinct axes

Telemetry is observational infrastructure; it does not perform autonomous redesign.

### 5. Inject Health/Cohesion Signals into `<known_tools>`

Extend prompt-time known-tools metadata with concise health signals:

1. canonical methods
2. recent boundary/usefulness failures
3. cohesion warning summary

The Tool Builder uses this signal to:

1. refine contract acceptance criteria,
2. split or recompose tools when boundary mismatch repeats,
3. retain existing interfaces when health is strong.

### 6. Inline Correction Lane (Hot Path)

Inline behavior on active calls:

1. enforce deliverable boundary checks (ADR 0014);
2. allow Tool self-referral (`wrong_tool_boundary`) and usefulness signaling (`low_utility`);
3. perform immediate repair/retry only for implementation failures that block the current call;
4. avoid heavy architectural reasoning in-line when deterministic completion is possible.

Inline lane goal: correct now, fail typed, keep caller flow coherent.

### 7. Out-of-Band Evolution Lane (Maintenance Path)

Out-of-band behavior over accumulated traces:

1. evaluate repeated low-utility and boundary signals;
2. cluster failures by boundary axes and compute cohesion warnings;
3. surface actionable evolution suggestions to Tool Builder (split/recompose/tighten acceptance);
4. schedule re-forge/refinement outside latency-sensitive user calls.

Out-of-band lane goal: evolve durable tool architecture from evidence without overloading hot-path calls.

### 8. Ground-Truth Signal: User Corrections

Capture explicit user-correction events as first-class telemetry, for example:

1. "that doesn't look like a movie list"
2. "this is a menu, not titles"
3. "try again, this output is not useful"

These are high-signal utility labels from real interaction and should be treated as stronger than model self-assessment when scoring `low_utility`.

### 9. Evolution Policy: Observation, Not Prescription

Runtime responsibilities:

1. classify outcomes,
2. persist telemetry,
3. surface signals in both inline and out-of-band lanes.

Tool Builder responsibilities:

1. decide whether to refine implementation,
2. tighten contract semantics,
3. split or recompose tool boundaries.

Runtime must not auto-split tools in v1.

## Scope

In scope:

1. new typed outcome semantics (`wrong_tool_boundary`, `low_utility`);
2. metadata schema for boundary referral;
3. telemetry persistence and prompt injection for cohesion signals;
4. Tool-depth prompt nudge for spirit-of-contract self-evaluation;
5. user-correction telemetry capture and scoring;
6. dual-lane (inline + out-of-band) repair/evolution policy wiring based on typed outcomes.

Out of scope:

1. runtime-autonomous tool decomposition;
2. hardcoded domain heuristics for specific websites/data sources;
3. mandatory universal split patterns (for example forcing `http_client` + `html_parser` in all cases).

## Consequences

### Positive

1. turns ambiguous failures into explicit architectural signals;
2. improves Tool Builder decision quality with evidence instead of guesswork;
3. preserves emergence: runtime observes, agents decide;
4. reduces persistence of low-value but shape-valid artifacts;
5. aligns with Tool Builder/Tool/Worker ubiquitous language;
6. prevents hot-path latency from ballooning due to constant deep self-evaluation.

### Tradeoffs

1. more telemetry state and prompt tokens;
2. potential overuse of `wrong_tool_boundary` if nudge is too aggressive;
3. cohesion scoring thresholds require tuning to avoid false positives;
4. requires an asynchronous evaluation loop and operational visibility for out-of-band evolution;
5. user-correction extraction must avoid overfitting to ambiguous language.

## Alternatives Considered

1. Keep only execution/contract errors
   - Rejected: conflates crash, mismatch, and referral semantics.
2. Add many new contract fields for robustness
   - Rejected: schema growth is not the bottleneck; contract quality and failure feedback loop are.
3. Runtime auto-splits tools on repeated failures
   - Rejected: violates agent-first architecture decisions.
4. Hardcode robust fetch/extract primitives in runtime
   - Rejected for this phase: conflicts with emergent tool evolution goal.
5. Perform all evaluation inline only
   - Rejected: adds avoidable latency/cognitive load to normal calls and slows deterministic tasks.

## Rollout Plan

### Phase 1: Typed Outcomes and Metadata

1. Add `wrong_tool_boundary` and `low_utility` to outcome taxonomy.
2. Normalize referral metadata shape.
3. Add tests for coercion/logging/serialization of these outcomes.

### Phase 2: Telemetry Persistence

1. Persist boundary/usefulness signals in artifacts and registry metadata.
2. Track axis clustering and rolling cohesion warning.
3. Capture explicit `user_correction` events in trace metadata.
4. Add tests for persistence and backward compatibility.

### Phase 3: Inline Correction Lane

1. Add Tool-depth spirit-of-contract self-evaluation nudge, scoped to plausibly low-utility tasks.
2. Add inline classification policy:
   - `execution`/`contract_violation` -> immediate correction path;
   - `wrong_tool_boundary`/`low_utility` -> typed referral and continue.
3. Add acceptance tests showing typed referral behavior without hard crashes.

### Phase 4: Out-of-Band Evolution Lane

1. Inject tool health/cohesion summary in `<known_tools>`.
2. Route repeated boundary signals to Tool Builder contract refinement paths.
3. Bias repair/evolution policy:
   - implementation failures -> repair implementation;
   - boundary/usefulness failures -> recommend contract/tool decomposition.
4. Weight repeated `user_correction` signals as high-confidence evidence for `low_utility`.
5. Add trace-based acceptance tests for repeated-boundary scenario and delayed evolution.

## Guardrails

1. `wrong_tool_boundary` is referral semantics, not a silent escape hatch.
2. Tool must include short evidence metadata when emitting boundary referral.
3. Tool Builder remains responsible for final decomposition decisions.
4. Runtime surface should remain minimal and explainable.
5. Inline lane must prefer fast correction/referral over deep architectural rewrites.
6. User-correction signals should influence evolution policy, not force immediate hardcoded behavior changes.

## Open Questions

1. Axis vocabulary governance:
   - fixed enum in v1, or agent-defined axes with normalization?
   - v1 direction: agent-defined axes with lightweight runtime normalization.
2. Cohesion warning thresholds:
   - count-based, recency-weighted, or blended?
3. Should repeated `low_utility` at Tool depth count as adaptive failure for artifact selection?
   - v1 direction: yes, count repeated `low_utility` as adaptive failure.
4. How much health detail can be injected in `<known_tools>` before prompt budget tradeoffs outweigh value?
