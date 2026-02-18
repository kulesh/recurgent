# Philosophy Adherence Implementation Plan

## Objective

Bring the codebase into alignment with its own design philosophy — *design bicycles, not Rube Goldberg machines* — without regressions or feature removal. Every subsystem earns its place against what the system promises to do. The problem is decomposition granularity: 51 implementation files is over-fragmented for the concerns they represent, while the test suite has the inverse problem (83% of tests in one file).

## Problem Statement

The system promises inside-out LLM tool calling with delegation contracts, cross-session persistence, guardrails, dependency isolation, pattern memory, and full observability. These are real, load-bearing concerns. But the current file structure fractures them into satellite modules that are too small to justify their own files:

- **17 modules under 60 lines** — each adds a file, a `require_relative`, an `include`, and a unit of navigation cost, but contains only 1–3 methods
- **7 parent modules that `include` satellites** — the satellites exist only because their parent was getting long, not because they represent independent concerns
- **1 monolithic test file (3,397 lines, 204 tests)** — the inverse problem: testing granularity is too coarse despite implementation granularity being too fine
- **prompting.rb at 894 lines** — the single largest source of accidental complexity, with data encoded as code

The cognitive cost of navigating 51 files exceeds the organizational benefit. Every developer opening this codebase must build a mental model of 51 module boundaries before they can understand the dispatch path. The philosophy demands: find ways to remove complexity without losing leverage.

## Design Principles Applied

1. **Simple is Always Better** — Consolidate satellite modules into their parent concerns. A 300-line file with clear internal structure is simpler than 5 files averaging 60 lines.
2. **Obsess Over Details** — Fix the gemspec URLs, the broken example, the stale RuboCop exclusion.
3. **Craft, Don't Code** — The dispatch narrative should be readable by tracing ~25 files, not ~50.
4. **Iterate Relentlessly** — Each phase produces a testable result. The test suite runs green after every merge.

## Solution Options

### Option A: Status quo with documentation improvements only
- Pros: Zero risk.
- Cons: Does not address the structural tension. New contributors still face 51-file navigation.

### Option B (Recommended): Consolidate satellites into parents, decompose test monolith, tighten prompting
- Pros: Reduces navigation cost by ~50%, mirrors concern boundaries in both implementation and tests, removes accidental complexity from prompting, fixes defects.
- Cons: Large refactoring surface requires disciplined per-merge test validation.

### Option C: Aggressive consolidation into fewer, larger modules
- Pros: Maximally simple file structure.
- Cons: Individual files become unwieldy (500+ lines), harder to review diffs, diminishing returns past the satellite-merge threshold.

## Phased Plan

### Phase 0: Fix Defects

Low-risk, high-signal fixes that demonstrate adherence to Principle 6 (Obsess Over Details).

| Defect | File | Fix |
|--------|------|-----|
| Gemspec URLs reference `kulesh/actuator` | `recurgent.gemspec:10–18` | Update all metadata URLs to correct repository |
| csv_explorer references non-existent `gpt-5.2-codex` | `examples/csv_explorer.rb:6` | Replace with a valid model constant |
| `Security/Eval` exclusion targets wrong file | `.rubocop.yml` | `lib/recurgent.rb` no longer contains eval; `execution_sandbox.rb` uses `instance_eval` which is not covered by this cop — remove the stale exclusion entirely |

**Verification:** `rake` passes (specs + rubocop).

### Phase 1: Consolidate Satellite Modules

Merge small satellite modules into their logical parent. Each merge is one atomic step: inline the satellite's methods into the parent, remove the satellite file, remove its `require_relative` and `include`, run `rake`. The `include` chain disappears because the methods now live directly in the parent module.

All modules are mixed into `Agent`, so every private method is already accessible to every other module. Merging is purely about file organization — zero behavioral change.

#### 1A: Observability cluster (3 → 1)

| Satellite | Lines | Merges Into |
|-----------|------:|-------------|
| `observability_history_fields.rb` | 17 | `observability.rb` |
| `observability_attempt_fields.rb` | 30 | `observability.rb` |
| `json_normalization.rb` | 38 | `observability.rb` |

**Result:** `observability.rb` grows from 182 → ~267 lines. One file owns all logging, tracing, JSON safety, and field mapping.

#### 1B: Artifact cluster (5 → 1)

| Satellite | Lines | Merges Into |
|-----------|------:|-------------|
| `artifact_trigger_metadata.rb` | 22 | `artifact_store.rb` |
| `artifact_metrics.rb` | 88 | `artifact_store.rb` |
| `artifact_selector.rb` | 65 | `artifact_store.rb` |
| `artifact_repair.rb` | 111 | `artifact_store.rb` |
| `persisted_execution.rb` | 98 | `artifact_store.rb` |

**Result:** `artifact_store.rb` grows from 189 → ~573 lines. Consider splitting into two sections with clear comment headers: "Persistence" and "Execution/Repair". One file owns the complete artifact lifecycle: store, load, select, execute, repair, metrics.

**Rationale:** These 6 modules form a tight call chain (`PersistedExecution` → `ArtifactSelector` → `ArtifactStore` → `ArtifactRepair` → `ArtifactMetrics` → `ArtifactTriggerMetadata`). The data flow is linear and the modules share the same state (`CallState`, artifact JSON structure). Separating them provides no reuse benefit — they exist only within this lifecycle.

#### 1C: Tool registry cluster (5 → 2)

| Satellite | Lines | Merges Into |
|-----------|------:|-------------|
| `tool_store_paths.rb` | 42 | `tool_store.rb` |
| `tool_store_intent_metadata.rb` | 23 | `tool_store.rb` |
| `tool_registry_integrity.rb` | 62 | `tool_store.rb` |

`tool_maintenance.rb` (135 lines) stays separate — it's an operator-facing utility with its own spec file and distinct concern (stale tool pruning vs runtime registry operations).

**Result:** `tool_store.rb` grows from 195 → ~322 lines. One file owns registry persistence, path computation, integrity checks, and intent metadata.

#### 1D: Guardrail cluster (4 → 1)

| Satellite | Lines | Merges Into |
|-----------|------:|-------------|
| `guardrail_code_checks.rb` | 120 | `guardrail_policy.rb` |
| `guardrail_outcome_feedback.rb` | 57 | `guardrail_policy.rb` |
| `guardrail_boundary_normalization.rb` | 34 | `guardrail_policy.rb` |

**Result:** `guardrail_policy.rb` grows from 188 → ~399 lines. One file owns all guardrail concerns: policy decisions, code pattern checks, outcome feedback prompting, and boundary normalization.

#### 1E: Outcome contract cluster (3 → 1)

| Satellite | Lines | Merges Into |
|-----------|------:|-------------|
| `outcome_contract_shapes.rb` | 138 | `outcome_contract_validator.rb` |
| `outcome_contract_constraints.rb` | 111 | `outcome_contract_validator.rb` |

**Result:** Rename `outcome_contract_validator.rb` → `outcome_contract.rb` (362 lines). One file owns all contract validation: shape checks, constraint checks, and the validator orchestration.

#### 1F: Conversation history cluster (2 → 1)

| Satellite | Lines | Merges Into |
|-----------|------:|-------------|
| `conversation_history_normalization.rb` | 132 | `conversation_history.rb` |

**Result:** `conversation_history.rb` grows from 165 → ~297 lines. One file owns history recording and normalization.

#### 1G: Pattern memory cluster (4 → 1)

| Satellite | Lines | Merges Into |
|-----------|------:|-------------|
| `pattern_prompting.rb` | 120 | `pattern_memory_store.rb` |
| `capability_pattern_extractor.rb` | 72 | `pattern_memory_store.rb` |
| `user_correction_signals.rb` | 113 | `pattern_memory_store.rb` |

**Result:** Rename `pattern_memory_store.rb` → `pattern_memory.rb` (~495 lines). One file owns capability pattern extraction, memory persistence, prompt generation, and correction signal detection.

**Rationale:** These modules form a pipeline. `CapabilityPatternExtractor` feeds `PatternMemoryStore`, which feeds `PatternPrompting`. `UserCorrectionSignals` consumes pattern memory events. Separating them into 4 files obscures the pipeline's linear data flow.

#### 1H: Delegation cluster (2 → 1)

| Satellite | Lines | Merges Into |
|-----------|------:|-------------|
| `delegation_intent.rb` | 55 | `delegation_options.rb` |

**Result:** Rename `delegation_options.rb` → `delegation.rb` (~102 lines). One file owns intent inference and option partitioning.

#### 1I: Fresh generation cluster (2 → 1)

| Satellite | Lines | Merges Into |
|-----------|------:|-------------|
| `fresh_outcome_repair.rb` | 86 | `fresh_generation.rb` |

**Result:** `fresh_generation.rb` grows from 254 → ~340 lines. One file owns the complete fresh-call lifecycle: generation loop, retry state management, and outcome repair routing.

#### 1J: Attempt tracking cluster (2 → 1)

| Satellite | Lines | Merges Into |
|-----------|------:|-------------|
| `attempt_failure_telemetry.rb` | 61 | `attempt_isolation.rb` |

**Result:** Rename `attempt_isolation.rb` → `attempt_tracking.rb` (~141 lines). One file owns snapshot/restore and failure telemetry — both are per-attempt lifecycle concerns.

#### 1K: Worker cluster (keep 4 → consider 3)

| File | Lines | Action |
|------|------:|--------|
| `worker_executor.rb` | 107 | Keep |
| `worker_execution.rb` | 151 | Keep |
| `worker_entrypoint.rb` | 123 | Keep |
| `worker_supervisor.rb` | 77 | Keep |

Worker modules stay separate. `worker_entrypoint.rb` runs in a subprocess — it has a fundamentally different execution context. `worker_supervisor.rb` manages lifecycle. `worker_executor.rb` manages IPC. `worker_execution.rb` handles payload encoding. These are genuinely independent concerns despite their small size. The subprocess boundary justifies the file boundary.

However, evaluate merging `worker_execution.rb` (payload encoding) into `worker_executor.rb` (IPC lifecycle) during implementation if the coupling is tight. This would yield 3 worker files.

#### Phase 1 Summary

| Metric | Before | After |
|--------|-------:|------:|
| Implementation files | 51 | ~27 |
| `require_relative` lines in `recurgent.rb` | 50 | ~26 |
| `include` lines in Agent class | 30 | ~17 |
| Median file size | ~88 lines | ~190 lines |
| Max file size (excl. prompting) | 254 lines | ~573 lines |

**Verification after each merge:** `rake` passes (specs + rubocop). Run after *every individual merge*, not in batch.

### Phase 2: Decompose the Monolithic Test File

Split `recurgent_spec.rb` (3,397 lines, 204 tests) into concern-focused files. This is the inverse of Phase 1 — the test suite is under-decomposed.

The existing top-level `describe` blocks provide natural split points:

| Target File | Source Describes | Tests | Lines (est.) |
|-------------|-----------------|------:|-------------:|
| `spec/agent/initialization_spec.rb` | `#initialize`, `provider auto-detection`, `error types` | 24 | ~450 |
| `spec/agent/coordination_spec.rb` | `coordination primitives`, `tool registry persistence`, `artifact persistence`, `delegated outcome contract validation` | 38 | ~750 |
| `spec/agent/dispatch_spec.rb` | `attribute assignment`, `method calls`, `verbose mode`, `#inspect`, `#to_s`, `#respond_to_missing?` | 56 | ~800 |
| `spec/agent/delegation_spec.rb` | `delegation`, `dependency environment behavior`, `.prepare` | 16 | ~450 |
| `spec/agent/prompting_spec.rb` | `prompt construction`, `capability pattern extraction and memory` | 20 | ~500 |
| `spec/agent/observability_spec.rb` | `logging` | 38 | ~500 |
| `spec/agent/providers_spec.rb` | `Agent::Providers::Anthropic`, `Agent::Providers::OpenAI` | 9 | ~180 |

Each file requires `spec_helper` and shares the same mock provider setup (extract to a shared context or `spec/support/` helper).

**Verification:** Total test count remains 204. `rake spec` passes. No test rewriting — only file relocation with shared setup extraction.

### Phase 3: Tighten Prompting

`prompting.rb` at 894 lines is the largest source of accidental complexity. The issue is not that the prompts are wrong — they're carefully crafted. The issue is that **data is encoded as code**.

#### 3A: Extract capability heuristic rules to a frozen constant

Lines 616–630: a list of `[tag, regex]` pairs.

```ruby
# Before: inline in method body
def _heuristic_tool_capabilities(text)
  capability_rules = [
    ["http_fetch", /\b(http|https|url|fetch|net::http)\b/],
    ...
  ]
  capability_rules.select { ... }.map(&:first)
end

# After: frozen constant
CAPABILITY_HEURISTIC_RULES = [
  ["http_fetch", /\b(http|https|url|fetch|net::http)\b/],
  ...
].freeze

def _heuristic_tool_capabilities(text)
  CAPABILITY_HEURISTIC_RULES.select { |(_, pattern)| text.match?(pattern) }.map(&:first)
end
```

#### 3B: Reduce example pattern count and size

Lines 649–841 (192 lines): 8 example patterns at depth 0, 3 at depth 1, 2 at depth 2. Several overlap in what they teach the LLM:

- `capability_limited_error` appears identically at all 3 depths (3 copies)
- `delegation_with_contract` and `forge_reusable_capability` teach similar delegation patterns
- `reuse_known_tool` (33 lines) contains more registry-querying code than most generated programs — it's fighting the LLM's tendency to over-query rather than teaching a clean pattern

Proposed reductions:
- Deduplicate `capability_limited_error` — emit once, reference from all depths
- Merge `delegation_with_contract` and `forge_reusable_capability` into one delegation example
- Simplify `reuse_known_tool` to ~10 lines (query → materialize → call → handle)
- Target: depth-0 examples from 8 → 5 patterns, total prompt size reduction ~40–60 lines

#### 3C: Consolidate tool metadata extraction

Lines 484–645 (~160 lines): 15 methods for extracting purpose, methods, capabilities, intent signatures, and aliases from tool metadata hashes. Many follow an identical pattern:

```ruby
def _extract_tool_X(metadata)
  return DEFAULT unless metadata.is_a?(Hash)
  Array(metadata[:X] || metadata["X"]).map { ... }.reject(&:empty?).uniq
end
```

Extract a generic `_extract_tool_list_field(metadata, key)` helper and reduce the 15 methods to ~8.

#### 3D: Remove the `rubocop:disable Metrics/ModuleLength` suppression

After 3A–3C, `prompting.rb` should be under 750 lines. If still over the 160-line ModuleLength limit, that limit is too aggressive for a module whose job is prompt construction — adjust the RuboCop config with a per-file override rather than an inline suppression. Inline `rubocop:disable` comments are a smell; configuration overrides are intentional.

Similarly, remove the `rubocop:disable Metrics/ModuleLength` from `fresh_generation.rb` after Phase 1I merges `fresh_outcome_repair.rb` into it — verify the combined module's length against the limit.

#### 3E: Evaluate `_known_tools_system_prompt` duplication

Tool registry data appears in both the system prompt (via `_known_tools_system_prompt`) and the user prompt (via `_known_tools_prompt` + `_known_tools_usage_hint`). This doubles the token cost for tool metadata. Evaluate whether the system prompt inclusion can be removed without degrading LLM tool-reuse behavior (requires a baseline comparison against `docs/baselines/`).

**Verification:** `rake` passes. Baseline comparison for 3E if changes affect prompt content.

### Phase 4: Strengthen Acceptance Coverage

The acceptance suite (`spec/acceptance/recurgent_acceptance_spec.rb`) covers 6 scenarios in 136 lines. The system promises at least 9 major capabilities. Each capability deserves at least one end-to-end acceptance scenario with a deterministic mock provider.

Missing acceptance coverage:

| Capability | Current Coverage | Gap |
|------------|-----------------|-----|
| Basic method dispatch | Covered | — |
| Setter assignment | Covered | — |
| Delegation with contracts | Covered | — |
| Cross-session artifact persistence | Not covered | Add: persist artifact, reload, verify reuse |
| Pattern memory pipeline | Not covered | Add: extract pattern, record event, verify memory |
| Guardrail violation + recovery | Not covered | Add: trigger violation, verify recovery prompt, verify corrected output |
| Dependency-backed worker execution | Not covered | Add: declare dependency, verify worker invocation |
| Conversation history recording | Not covered | Add: multi-call sequence, verify history structure |
| Outcome contract validation | Not covered | Add: delegation with deliverable contract, verify enforcement |

Target: 15 acceptance scenarios covering all promised capabilities.

**Verification:** `rake spec` passes with increased acceptance count.

### Phase 5: Documentation and Index Update

1. Update `docs/plans/README.md` to include this plan.
2. Update the information index in `CLAUDE.md` per the "Information Organization" instruction.
3. Write an ADR for the consolidation rationale (ADR 0023: Module Consolidation for Navigability).
4. Update `docs/architecture.md` to reflect the consolidated module map.

## Work Breakdown

### Implementation Order

Phases are sequential. Within Phase 1, merges are independent and can be done in any order, but each individual merge must be verified before the next.

```
Phase 0  →  Phase 1A → 1B → 1C → 1D → 1E → 1F → 1G → 1H → 1I → 1J → 1K
         →  Phase 2 (can begin after Phase 1 is complete)
         →  Phase 3 (can begin after Phase 2 is complete — test decomposition first so prompt changes are tested against the new structure)
         →  Phase 4 (can begin after Phase 3 is complete)
         →  Phase 5 (runs last)
```

### Verification Protocol

Every phase boundary requires:
1. `bundle exec rspec` — all tests pass, no new failures
2. `bundle exec rubocop` — no new offenses
3. `git diff --stat` — review confirms only the intended files changed
4. No behavioral changes — same test count, same test names (Phase 2 moves but does not modify tests)

## Risks and Mitigations

1. **Merge introduces subtle method shadowing.** Mitigation: All modules are already mixed into Agent — merging files does not change method resolution order. Run `rake` after each merge.
2. **Test decomposition breaks shared setup.** Mitigation: Extract shared mock provider and helper methods into `spec/support/` before splitting. Verify total test count is preserved.
3. **Prompt tightening degrades LLM behavior.** Mitigation: Phase 3E (system prompt deduplication) is evaluated against baselines before committing. Phases 3A–3D are structural (constant extraction, deduplication) and do not change prompt semantics.
4. **Large diff in Phase 1B (artifact cluster, 5 files → 1).** Mitigation: Merge one satellite at a time, not all 5 simultaneously. Five atomic commits, each verified independently.

## Acceptance Criteria

1. Implementation file count reduced from 51 to ~27 without removing any functionality.
2. Test file count increased from 1 monolithic + 8 focused to 7 focused + 8 focused.
3. `prompting.rb` reduced from 894 lines to under 750, with zero inline `rubocop:disable` suppressions.
4. All defects from Phase 0 resolved.
5. Acceptance test coverage expanded from 6 to 15 scenarios.
6. `rake` passes at every phase boundary.
7. No ADRs invalidated — every existing subsystem retains its functionality.

## Decisions Captured

1. The 51-module structure is over-fragmented for the concerns it represents.
2. Satellites under ~130 lines that are `include`d by exactly one parent should merge into that parent.
3. Worker modules stay separate because the subprocess boundary justifies the file boundary.
4. `tool_maintenance.rb` stays separate because it's an operator-facing utility with a distinct concern.
5. Test decomposition follows the existing top-level `describe` blocks as natural split points.
6. Prompt tightening preserves semantics; only structural changes (constant extraction, deduplication, simplification) are in scope.
