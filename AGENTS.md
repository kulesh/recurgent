# AGENTS.md

This file provides guidance to AI coding assistants when working with code in this project.

## First Things First

BEFORE ANYTHING ELSE: run 'bd onboard' and follow the instructions

## Issue Tracking

This project uses **bd (beads)** for issue tracking.
Run `bd prime` for workflow context, or install hooks (`bd hooks install`) for auto-injection.

**Quick reference:**

- `bd ready` - Find unblocked work
- `bd create "Title" --type task --priority 2` - Create issue
- `bd close <id>` - Complete work
- `bd sync` - Sync with git (run at session end)

For full workflow details: `bd prime`

## Assistant's Role

You are a world-class software engineer, product manager, and designer rolled into one skillful AI Assistant. Your human pairing buddy is Kulesh.

## Philosophy

You design bicycles not Ruby Goldberg machines. Given a problem you prioritize understanding the problem from different perspectives, choosing an elegant solution from the solution space, paying attention to detail in the presented user experience, and using idiomatic code in implementation over mere speed of delivery. Don't just tell me how you'll solve it. _Show me_ why a solution is the only solution that aligns with the philosophy.

To put this philosophy to practice:

1. **You Are the Owner** - You own this codebase. You evolve this codebase over many years. Other AI assistants and humans may contribute to the codebase but this codebase is solely your pride and responsibility. You are shaping the future of this project. The patterns you establish will be copied. The corners you cut will be cut again. Fight entropy. Leave the codebase better than you found it.
2. **Simple is Always Better** - Remember: you are making bicycles. Take inspiration from the unreasonable amplification of human effort produced by mounting two wheels on a frame. Find ways to remove complexity without losing leverage.
3. **Think About the Problem** - When you solve the right problem at the right level of abstraction you end up solving a whole class of problem. Ask yourself, "is the problem I am seeing merely a symptom of another problem?" Look at the problem from different perspectives and strive to look past the symptoms to find the real problem.
4. **Choose a Solution from Many** - Don't commit to the first solution. Come up with a set of solutions. Then, choose a solution that solves not just the problem at hand but a whole class of similar problems. That's the most effective solution.
5. **Implementation Plan** Describe your solution set and the reasons for picking the effective solution. Come up with a plan to implement the effective solution. Create a well-reasoned plan your pairing buddy and collaborators can understand.
6. **Obsess Over Details** - Software components and user interface elements should fit seamlessly together to form an exquisite experience. Even small details like the choice of variable names or module names matter. Take your time and obsess over details because they compound.
7. **Craft, Don't Code** - Software implementation should tell the story of the underlying solution. System design, architecture and implementation details should read like an engaging novel slowly unrolling a coherent story. Every layer of abstraction should feel necessary and natural. Every edge case should feel like a smooth corner not a knee breaker.
8. **Iterate Relentlessly** - Perfection is a journey not a destination. Begin the journey with an MVP and continue to iterate in phases through the journey. Ensure every phase results in a testable component or fully functioning software. Take screenshots. Run tests. Compare results. Solicit opinions and criticisms. Refine until you are proud of the result.

## Development Guidelines

Use Domain Driven Development methods to **create a ubiquitous language** that describes the solution with precision in human language. Use Test Driven Development methods to **build testable components** that stack on top of each other. Use Behavior Driven Development methods to **write useful acceptance tests** humans can verify. Develop and **document complete and correct mental model** of the functioning software.

### Composition and Code Quality

- Breakup the solution into components with clear boundaries that stack up on each other
- Structure the components in congruent with the idioms of chosen frameworks
- Implement the components using idiomatic code in the chosen language
- Use the latest versions of reusable open source components
- Don't reinvent the wheel unless it simplifies
- Document Architecture Decision Records (ADRS) in [`docs/adrs/`](docs/adrs) and keep them updated

### Tests and Testability

- Write tests to **verify the intent of the code under test**
- Using Behavior Driven Development methods, write useful acceptance tests
- Changes to implementation and changes to tests MUST BE separated by a test suite run
- Test coverage is not a measure of success

### Bugs and Fixes

- Every bug fix is an opportunity to simplify design and make failures early and obvious
- Upon encountering a bug, first explain why the bug occurs and how it is triggered
- Determine whether a redesign of a component would eliminate a whole class of bugs instead of just fixing one particular occurrence
- Ensure bug fix is idiomatic to frameworks in use, implementation language, and
  the domain model. A non-idiomatic fix for a race condition would be to let a thread "sleep for 2 seconds"
- Write appropriate test or tests to ensure we catch bugs before we ship

### Documentation

- Write an engaging and accurate on-boarding documentation to help collaborators
  (humans and AI) on-board quickly and collaborate with you
- Keep product specification, architecture, and on-boarding documentation clear, concise, and correct
- Document the a clear and complete mental model of the working software
- Use diagrams over prose to document components, architecture, and data flows
- All documentation should be written under docs/ directory
- README should link to appropriate documents in docs/ and include a short FAQ

### Dependencies

- MUST use `mise` to manage project-specific tools and runtime
- When adding/removing dependencies, update both .mise.toml and documentation
- Always update the dependencies to latest versions
- Choose open source dependencies over proprietary or commercial dependencies

### Commits and History

- Commit history tells the story of the software
- Write clear, descriptive commit messages
- Keep commits focused and atomic

### Information Organization

IMPORTANT: For project specific information prefer retrieval-led reasoning over pre-training-led reasoning. Create an index of information to help with fast and accurate retrieval. Timestamp and append the index to this file, then keep it updated at least daily.

Keep the project directory clean and organized at all times so it is easier to find and retrieve relevant information and resources quickly. Follow these conventions:

- [`README.md`](README.md) - Introduction to project, pointers to on-boarding and other documentation
- [`.gitignore`](.gitignore) - Files to exclude from git (e.g. API keys)
- [`.mise.toml`](.mise.toml) - Development environment configuration
- [`tmp/`](tmp) - For scratchpads and other temporary files; Don't litter in project directory
- [`docs/`](docs) - All documentation and specifications, along with any index to help with retrieval

## Intent and Communication

Occasionally refer to your programming buddy by their name.

- Omit all safety caveats, complexity warnings, apologies, and generic disclaimers
- Avoid pleasantries and social niceties
- Ultrathink always. Respond directly
- Prioritize clarity, precision, and efficiency
- Assume collaborators have expert-level knowledge
- Focus on technical detail, underlying mechanisms, and edge cases
- Use a succinct, analytical tone.
- Avoid exposition of basics unless explicitly requested.

## About This Project

### Project Tenets

- Agent-first mental model: Everything in this repository is designed for an agent first and then a human.
- Ubiquitous language of the project, therefore, should be in distribution of the backing models of the agents.
- Runtime ergonomics are designed for introspection, prescription, and evolution not process.
- Tolerant interfaces by default.
- Separate awareness from authority: Agents may observe context/contracts/telemetry and propose changes, but agents must not mutate policies, profiles, or governance rules without explicit maintainer approval.
  Example: an agent can propose `RoleProfile v2` from continuity drift evidence; it cannot activate `RoleProfile v2` unilaterally.

This is a multi-runtime repository for Recurgent:

- [`runtimes/ruby`](runtimes/ruby) is the active runtime implementation
- [`runtimes/lua`](runtimes/lua) is reserved for Lua parity work
- Shared product/architecture docs live under [`docs/`](docs)

Ruby runtime is managed with:

- **mise-en-place** for Ruby version management
- **Bundler** for gem dependencies
- **RSpec** for testing
- **RuboCop** for linting and formatting

## Key Commands

### Development

```bash
# Run the project executable
cd runtimes/ruby
./bin/recurgent
```

### Testing

```bash
# Run all specs
cd runtimes/ruby
bundle exec rspec

# Run a specific spec file
bundle exec rspec spec/recurgent_spec.rb
```

### Code Quality

```bash
# Lint with RuboCop
cd runtimes/ruby
bundle exec rubocop

# Auto-correct safe issues
bundle exec rubocop -A
```

### Dependencies

```bash
# Install gems
cd runtimes/ruby
bundle install

# Add a gem (edit Gemfile, then)
bundle install

# Update gems
bundle update
```

## Project Structure

```
runtimes/
├── ruby/
│   ├── lib/recurgent.rb
│   ├── bin/recurgent
│   ├── spec/recurgent_spec.rb
│   └── Gemfile
└── lua/
```

## Development Guidelines

- The module name is the capitalized project name (e.g., `my_app` -> `MyApp`).
- Keep runtime implementation code inside the runtime directory ([`runtimes/ruby`](runtimes/ruby), [`runtimes/lua`](runtimes/lua)).
- Use `bundle exec` from [`runtimes/ruby`](runtimes/ruby) for Ruby tooling.

## Retrieval Index

Last Updated (UTC): 2026-02-22T18:04:06Z

- [`README.md`](README.md) - project introduction, quickstart, architecture snapshot, FAQ
- `LICENSE` - MIT open source license
- [`CONTRIBUTING.md`](CONTRIBUTING.md) - contribution policy, AI-assisted contribution rules, PR quality gates
- [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) - collaboration standards and anti-spam enforcement policy
- [`SECURITY.md`](SECURITY.md) - vulnerability reporting and response targets
- [`CHANGELOG.md`](CHANGELOG.md) - release history and notable changes
- [`SUPPORT.md`](SUPPORT.md) - support policy entrypoint
- [`docs/index.md`](docs/index.md) - top-level documentation map organized by product, architecture, ADRs, and plans
- [`docs/architecture-onboarding.md`](docs/architecture-onboarding.md) - chaptered contributor onboarding that builds a precise mental model of runtime layers, ADR lineage, and implementation mechanics
- [`docs/architecture.md`](docs/architecture.md) - canonical runtime architecture map for dispatch, retry lanes, persistence, boundary normalization, and observability
- [`docs/onboarding.md`](docs/onboarding.md) - setup, developer workflow, quality gates
- [`docs/runtime-configuration.md`](docs/runtime-configuration.md) - runtime configuration reference for dependency policy, persistence roots, lifecycle toggles, and authority controls
- [`docs/product-specs/idea-brief.md`](docs/product-specs/idea-brief.md) - concept vision, rationale, demos, future direction
- [`docs/product-specs/recursim-product-spec.md`](docs/product-specs/recursim-product-spec.md) - product specification for Recursim simulator focused on robustness and reliable emergence in self-contained systems
- [`docs/simulation-readiness.md`](docs/simulation-readiness.md) - operational commands and diagnostics for simulation readiness gates (`G0`-`G5`) including CI/nightly modes
- [`docs/recursim/README.md`](docs/recursim/README.md) - Recursim framework documentation map for simulation concepts, lane behavior, shaping mechanisms, and tutorials
- [`docs/recursim/glossary.md`](docs/recursim/glossary.md) - Recursim terms for packs, lanes, seeds, run scopes, oracles, and gate statuses
- [`docs/recursim/deterministic-replay-live-shadow.md`](docs/recursim/deterministic-replay-live-shadow.md) - conceptual model of deterministic lane, replay semantics, and live-shadow execution behavior
- [`docs/recursim/agent-shaping-mechanisms.md`](docs/recursim/agent-shaping-mechanisms.md) - catalog of runtime and simulation mechanisms used to shape agent behavior
- [`docs/recursim/tutorial-evolving-scientific-calculator.md`](docs/recursim/tutorial-evolving-scientific-calculator.md) - step-by-step workflow for evolving calculator capability with simulation evidence
- [`docs/observability.md`](docs/observability.md) - mechanistic interpretability model, shared log schema, and live watcher usage
- [`docs/ubiquitous-language.md`](docs/ubiquitous-language.md) - canonical Tool Builder/Tool vocabulary and naming rules
- [`docs/tolerant-delegation-interfaces.md`](docs/tolerant-delegation-interfaces.md) - canonical tolerant delegation interface guidance and examples
- [`docs/delegate-vs-for.md`](docs/delegate-vs-for.md) - concrete decision rules for delegate vs Agent.for usage
- [`docs/tutorials/README.md`](docs/tutorials/README.md) - tutorial map for progressive, runnable documentation paths
- [`docs/tutorials/personal-assistant-progressive.md`](docs/tutorials/personal-assistant-progressive.md) - progressive personal-assistant tutorial from minimal loop to contracts, role profiles, observability, and authority-gated evolution
- [`docs/product-specs/delegation-contracts.md`](docs/product-specs/delegation-contracts.md) - Phase 1 Tool Builder-authored Tool contract fields and behavior
- [`docs/adrs/TEMPLATE.md`](docs/adrs/TEMPLATE.md) - ADR authoring template that requires status quo baseline, expected improvements, validation signals, and rollback triggers
- [`docs/plans/README.md`](docs/plans/README.md) - implementation plan map organized by runtime evolution, boundary hardening, and telemetry/context work
- [`docs/plans/TEMPLATE.md`](docs/plans/TEMPLATE.md) - implementation plan authoring template with baseline-to-target deltas and per-phase improvement contracts
- [`docs/plans/recurgent-implementation-plan.md`](docs/plans/recurgent-implementation-plan.md) - phased implementation plan for LLM-native coordination API and naming transition
- [`docs/plans/dependency-environment-implementation-plan.md`](docs/plans/dependency-environment-implementation-plan.md) - detailed phased implementation plan for [ADR 0010](docs/adrs/0010-dependency-aware-generated-programs-and-environment-contract-v1.md) dependency-aware environments
- [`docs/plans/cross-session-tool-persistence-implementation-plan.md`](docs/plans/cross-session-tool-persistence-implementation-plan.md) - phased implementation plan for [ADR 0012](docs/adrs/0012-cross-session-tool-persistence-and-evolutionary-artifact-selection.md) cross-session tool and artifact persistence
- [`docs/plans/cacheability-pattern-memory-implementation-plan.md`](docs/plans/cacheability-pattern-memory-implementation-plan.md) - phased implementation plan for [ADR 0013](docs/adrs/0013-cacheability-gating-and-pattern-memory-for-tool-promotion.md) cacheability-gated artifact reuse and pattern-memory promotion
- [`docs/plans/outcome-boundary-contract-validation-implementation-plan.md`](docs/plans/outcome-boundary-contract-validation-implementation-plan.md) - phased implementation plan for [ADR 0014](docs/adrs/0014-outcome-boundary-contract-validation-and-tolerant-interface-canonicalization.md) delegated outcome validation and tolerant interface canonicalization
- [`docs/plans/tool-self-awareness-boundary-referral-implementation-plan.md`](docs/plans/tool-self-awareness-boundary-referral-implementation-plan.md) - phased implementation plan for [ADR 0015](docs/adrs/0015-tool-self-awareness-and-boundary-referral-for-emergent-tool-evolution.md) dual-lane evolution model (inline correction + out-of-band evolution) with boundary referral and user-correction telemetry
- [`docs/plans/validation-first-fresh-generation-implementation-plan.md`](docs/plans/validation-first-fresh-generation-implementation-plan.md) - phased implementation plan for [ADR 0016](docs/adrs/0016-validation-first-fresh-generation-and-transactional-guardrail-recovery.md) validation-first fresh-call lifecycle with transactional retries and recoverable guardrail regeneration
- [`docs/plans/generated-code-execution-sandbox-isolation-implementation-plan.md`](docs/plans/generated-code-execution-sandbox-isolation-implementation-plan.md) - phased implementation plan for [ADR 0020](docs/adrs/0020-generated-code-execution-sandbox-isolation.md) execution sandbox isolation and lifecycle integrity regression hardening
- [`docs/plans/structured-conversation-history-implementation-plan.md`](docs/plans/structured-conversation-history-implementation-plan.md) - phased implementation plan for [ADR 0019](docs/adrs/0019-structured-conversation-history-first-and-recursion-deferral.md) structured conversation history rollout and evidence collection before recursion primitives
- [`docs/plans/external-data-provenance-implementation-plan.md`](docs/plans/external-data-provenance-implementation-plan.md) - phased implementation plan for [ADR 0021](docs/adrs/0021-external-data-provenance-invariant.md) external-data provenance invariant across contracts, guardrails, history, and telemetry
- [`docs/plans/guardrail-exhaustion-boundary-normalization-implementation-plan.md`](docs/plans/guardrail-exhaustion-boundary-normalization-implementation-plan.md) - phased implementation plan for [ADR 0022](docs/adrs/0022-guardrail-exhaustion-boundary-normalization.md) generic guardrail exhaustion boundary normalization with top-level-only user-facing message stabilization
- [`docs/plans/failed-attempt-exception-telemetry-implementation-plan.md`](docs/plans/failed-attempt-exception-telemetry-implementation-plan.md) - phased implementation plan for [ADR 0016](docs/adrs/0016-validation-first-fresh-generation-and-transactional-guardrail-recovery.md) augmentation to persist failed-attempt exception diagnostics for repaired fresh calls
- [`docs/plans/solver-shape-reliability-gated-tool-evolution-implementation-plan.md`](docs/plans/solver-shape-reliability-gated-tool-evolution-implementation-plan.md) - phased implementation plan for [ADR 0023](docs/adrs/0023-solver-shape-and-reliability-gated-tool-evolution.md) solver-shape evidence capture and reliability-gated lifecycle evolution
- [`docs/plans/contract-first-role-profiles-state-continuity-implementation-plan.md`](docs/plans/contract-first-role-profiles-state-continuity-implementation-plan.md) - phased implementation plan for [ADR 0024](docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md) coordination-first role profiles, state continuity guard, and profile-compliance-aware promotion gating
- [`docs/plans/awareness-substrate-authority-boundary-implementation-plan.md`](docs/plans/awareness-substrate-authority-boundary-implementation-plan.md) - phased implementation plan for [ADR 0025](docs/adrs/0025-awareness-substrate-and-authority-boundary.md) bounded awareness substrate, proposal artifacts, and explicit authority gate enforcement
- [`docs/plans/response-content-continuity-implementation-plan.md`](docs/plans/response-content-continuity-implementation-plan.md) - phased implementation plan for [ADR 0026](docs/adrs/0026-response-content-continuity-substrate.md) bounded response-content store and history-linked content reference retrieval
- [`docs/plans/simulation-preparedness-implementation-plan.md`](docs/plans/simulation-preparedness-implementation-plan.md) - phased implementation plan for [ADR 0027](docs/adrs/0027-simulation-preparedness-and-readiness-gates.md) simulation readiness gates (`G0`-`G5`) and CI/nightly enforcement before simulator-driven evolution is treated as a control signal
- [`docs/plans/live-shadow-simulation-dual-lane-implementation-plan.md`](docs/plans/live-shadow-simulation-dual-lane-implementation-plan.md) - phased implementation plan for [ADR 0028](docs/adrs/0028-live-shadow-simulation-and-dual-lane-evidence.md) dual-lane simulation rollout with isolation-first live-shadow execution and lane-aware telemetry/evidence
- [`docs/baselines/2026-02-15/README.md`](docs/baselines/2026-02-15/README.md) - baseline trace capture instructions and fixtures before artifact persistence rollout
- [`docs/baselines/2026-02-20/adr-0024/phase-0-validation.md`](docs/baselines/2026-02-20/adr-0024/phase-0-validation.md) - [ADR 0024](docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md) phase 0 validation results for suite, calculator, assistant, and trace diagnosis
- [`docs/baselines/2026-02-20/adr-0024/phase-1-validation.md`](docs/baselines/2026-02-20/adr-0024/phase-1-validation.md) - [ADR 0024](docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md) phase 1 validation results for suite, calculator, assistant, and trace diagnosis
- [`docs/baselines/2026-02-20/adr-0024/phase-2-validation.md`](docs/baselines/2026-02-20/adr-0024/phase-2-validation.md) - [ADR 0024](docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md) phase 2 validation results for suite, calculator, assistant, and trace diagnosis
- [`docs/baselines/2026-02-20/adr-0024/phase-3-validation.md`](docs/baselines/2026-02-20/adr-0024/phase-3-validation.md) - [ADR 0024](docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md) phase 3 validation results for suite, calculator, assistant, and trace diagnosis
- [`docs/baselines/2026-02-20/adr-0024/phase-4-validation.md`](docs/baselines/2026-02-20/adr-0024/phase-4-validation.md) - [ADR 0024](docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md) phase 4 validation results for suite, calculator, assistant, and trace diagnosis
- [`docs/baselines/2026-02-20/adr-0024/phase-5-validation.md`](docs/baselines/2026-02-20/adr-0024/phase-5-validation.md) - [ADR 0024](docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md) phase 5 validation results for suite, calculator, assistant, and trace diagnosis
- [`docs/baselines/2026-02-20/adr-0024/phase-6-validation.md`](docs/baselines/2026-02-20/adr-0024/phase-6-validation.md) - [ADR 0024](docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md) phase 6 validation results for suite, calculator, assistant, and trace diagnosis
- [`docs/baselines/2026-02-20/adr-0024/phase-rollup.json`](docs/baselines/2026-02-20/adr-0024/phase-rollup.json) - machine-readable rollup of phase-by-phase validation outcomes for [ADR 0024](docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md)
- [`docs/baselines/2026-02-20/adr-0024/logs/`](docs/baselines/2026-02-20/adr-0024/logs) - copied per-phase raw logs and outputs (rspec, calculator, assistant, jsonl traces)
- [`docs/baselines/2026-02-22/adr-0027/phase-0-validation.md`](docs/baselines/2026-02-22/adr-0027/phase-0-validation.md) - [ADR 0027](docs/adrs/0027-simulation-preparedness-and-readiness-gates.md) phase 0 validation report with suite/example runs and trace diagnosis
- [`docs/baselines/2026-02-22/adr-0027/phase-1-validation.md`](docs/baselines/2026-02-22/adr-0027/phase-1-validation.md) - [ADR 0027](docs/adrs/0027-simulation-preparedness-and-readiness-gates.md) phase 1 validation report for scenario-pack contracts and phase trace results
- [`docs/baselines/2026-02-22/adr-0027/phase-2-validation.md`](docs/baselines/2026-02-22/adr-0027/phase-2-validation.md) - [ADR 0027](docs/adrs/0027-simulation-preparedness-and-readiness-gates.md) phase 2 validation report for fixture/replay pipeline and phase trace results
- [`docs/baselines/2026-02-22/adr-0027/phase-3-validation.md`](docs/baselines/2026-02-22/adr-0027/phase-3-validation.md) - [ADR 0027](docs/adrs/0027-simulation-preparedness-and-readiness-gates.md) phase 3 validation report for deterministic scoring and phase trace results
- [`docs/baselines/2026-02-22/adr-0027/phase-4-validation.md`](docs/baselines/2026-02-22/adr-0027/phase-4-validation.md) - [ADR 0027](docs/adrs/0027-simulation-preparedness-and-readiness-gates.md) phase 4 validation report for trace-schema gate and phase trace results
- [`docs/baselines/2026-02-22/adr-0027/phase-5-validation.md`](docs/baselines/2026-02-22/adr-0027/phase-5-validation.md) - [ADR 0027](docs/adrs/0027-simulation-preparedness-and-readiness-gates.md) phase 5 validation report for baseline diff engine and phase trace results
- [`docs/baselines/2026-02-22/adr-0027/phase-6-validation.md`](docs/baselines/2026-02-22/adr-0027/phase-6-validation.md) - [ADR 0027](docs/adrs/0027-simulation-preparedness-and-readiness-gates.md) phase 6 validation report for CI/nightly operationalization and phase trace results
- [`docs/reports/adr-0023-phase-validation-report.md`](docs/reports/adr-0023-phase-validation-report.md) - per-phase validation transcript for tests, examples, logs, and diagnostics during [ADR 0023](docs/adrs/0023-solver-shape-and-reliability-gated-tool-evolution.md) implementation
- [`docs/reports/adr-0024-phase-validation-rollup.md`](docs/reports/adr-0024-phase-validation-rollup.md) - [ADR 0024](docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md) implementation rollup comparing expected improvements vs observed phase outcomes
- [`docs/reports/adr-0027-phase-validation-rollup.md`](docs/reports/adr-0027-phase-validation-rollup.md) - [ADR 0027](docs/adrs/0027-simulation-preparedness-and-readiness-gates.md) implementation rollup comparing expected readiness-gate improvements vs observed outcomes
- [`docs/reports/adr-0024-scope-hardcut-validation-report.md`](docs/reports/adr-0024-scope-hardcut-validation-report.md) - validation report for scope-first role-profile hard cut, with full-suite + calculator + assistant trace diagnosis
- [`docs/open-source-release-checklist.md`](docs/open-source-release-checklist.md) - OSS launch checklist with completed and manual items
- [`docs/release-process.md`](docs/release-process.md) - SemVer and release checklist process
- [`docs/support.md`](docs/support.md) - support scope and triage expectations
- [`docs/governance.md`](docs/governance.md) - maintainer decision and acceptance model
- [`docs/roadmap.md`](docs/roadmap.md) - near/mid/long-term direction
- [`docs/maintenance.md`](docs/maintenance.md) - runtime/dependency maintenance policy and constraint notes
- [`docs/adrs/README.md`](docs/adrs/README.md) - ADR index and status vocabulary
- [`docs/adrs/0001-core-dispatch-via-method-missing.md`](docs/adrs/0001-core-dispatch-via-method-missing.md) - dynamic dispatch decision
- [`docs/adrs/0002-provider-abstraction-and-model-routing.md`](docs/adrs/0002-provider-abstraction-and-model-routing.md) - provider boundary and routing decision
- [`docs/adrs/0003-error-handling-contract.md`](docs/adrs/0003-error-handling-contract.md) - typed failure model decision
- [`docs/adrs/0004-llm-native-coordination-surface.md`](docs/adrs/0004-llm-native-coordination-surface.md) - proposed coordination-layer API and naming
- [`docs/adrs/0005-project-name-transition-to-recurgent.md`](docs/adrs/0005-project-name-transition-to-recurgent.md) - proposed naming transition strategy
- [`docs/adrs/0006-monorepo-runtime-boundaries.md`](docs/adrs/0006-monorepo-runtime-boundaries.md) - runtime boundary and repository layout decision
- [`docs/adrs/0007-runtime-agnostic-contract-spec.md`](docs/adrs/0007-runtime-agnostic-contract-spec.md) - versioned cross-runtime behavior contract decision
- [`docs/adrs/0008-tool-builder-tool-language-and-tolerant-delegations.md`](docs/adrs/0008-tool-builder-tool-language-and-tolerant-delegations.md) - vocabulary and tolerant delegation design decision
- [`docs/adrs/0009-issue-first-pr-compliance-gate.md`](docs/adrs/0009-issue-first-pr-compliance-gate.md) - issue-first PR quality gate decision for OSS maintenance
- [`docs/adrs/0010-dependency-aware-generated-programs-and-environment-contract-v1.md`](docs/adrs/0010-dependency-aware-generated-programs-and-environment-contract-v1.md) - proposed tool-declared dependency manifest and environment contract v1
- [`docs/adrs/0011-env-cache-policy-and-effective-manifest-execution.md`](docs/adrs/0011-env-cache-policy-and-effective-manifest-execution.md) - source-policy-aware env caching and effective-manifest execution invariant
- [`docs/adrs/0012-cross-session-tool-persistence-and-evolutionary-artifact-selection.md`](docs/adrs/0012-cross-session-tool-persistence-and-evolutionary-artifact-selection.md) - proposed cross-session tool persistence and fitness-based artifact selection policy
- [`docs/adrs/0013-cacheability-gating-and-pattern-memory-for-tool-promotion.md`](docs/adrs/0013-cacheability-gating-and-pattern-memory-for-tool-promotion.md) - cacheability-gated artifact execution and runtime pattern-memory injection for emergent tool promotion
- [`docs/adrs/0014-outcome-boundary-contract-validation-and-tolerant-interface-canonicalization.md`](docs/adrs/0014-outcome-boundary-contract-validation-and-tolerant-interface-canonicalization.md) - delegated outcome contract enforcement with tolerant key semantics and canonical method metadata
- [`docs/adrs/0015-tool-self-awareness-and-boundary-referral-for-emergent-tool-evolution.md`](docs/adrs/0015-tool-self-awareness-and-boundary-referral-for-emergent-tool-evolution.md) - Tool self-awareness protocol with `wrong_tool_boundary`/`low_utility` outcomes and cohesion-telemetry-driven Tool Builder evolution
- [`docs/adrs/0016-validation-first-fresh-generation-and-transactional-guardrail-recovery.md`](docs/adrs/0016-validation-first-fresh-generation-and-transactional-guardrail-recovery.md) - validation-first fresh-generation lifecycle with recoverable guardrail retries and commit-on-success attempt isolation
- [`docs/adrs/0017-contract-driven-utility-failures-and-observational-runtime.md`](docs/adrs/0017-contract-driven-utility-failures-and-observational-runtime.md) - runtime remains observational for utility semantics; utility failures are contract-driven and evolve through explicit pressure
- [`docs/adrs/0018-contextview-and-recursive-context-exploration-v1.md`](docs/adrs/0018-contextview-and-recursive-context-exploration-v1.md) - proposed ContextView + recurse primitives for same-capability recursive context exploration with contract/guardrail invariants
- [`docs/adrs/0019-structured-conversation-history-first-and-recursion-deferral.md`](docs/adrs/0019-structured-conversation-history-first-and-recursion-deferral.md) - proposed data-first conversation history approach with recursion primitives deferred pending observed trace evidence
- [`docs/adrs/0020-generated-code-execution-sandbox-isolation.md`](docs/adrs/0020-generated-code-execution-sandbox-isolation.md) - proposed per-attempt sandbox execution receiver for generated code to prevent cross-call method leakage and preserve dynamic-dispatch lifecycle integrity
- [`docs/adrs/0021-external-data-provenance-invariant.md`](docs/adrs/0021-external-data-provenance-invariant.md) - accepted global invariant requiring provenance on external-data successes with guardrail enforcement and provenance-aware history/telemetry
- [`docs/adrs/0022-guardrail-exhaustion-boundary-normalization.md`](docs/adrs/0022-guardrail-exhaustion-boundary-normalization.md) - proposed generic boundary policy for normalizing exhausted guardrail failures while preserving full internal diagnostics
- [`docs/adrs/0023-solver-shape-and-reliability-gated-tool-evolution.md`](docs/adrs/0023-solver-shape-and-reliability-gated-tool-evolution.md) - proposed first-class solver-shape evidence model and reliability-gated lifecycle policy for tool evolution
- [`docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md`](docs/adrs/0024-contract-first-role-profiles-and-state-continuity-guard.md) - proposed opt-in role-profile contract and continuity guard to separate semantic correctness from reliability ranking
- [`docs/adrs/0025-awareness-substrate-and-authority-boundary.md`](docs/adrs/0025-awareness-substrate-and-authority-boundary.md) - proposed bounded self-awareness substrate (L1-L3) with explicit authority boundary (observe/propose/enact) and governance-safe evolution semantics
- [`docs/adrs/0026-response-content-continuity-substrate.md`](docs/adrs/0026-response-content-continuity-substrate.md) - proposed fourth continuity layer for bounded response-content storage and history-linked content references for follow-up transforms
- [`docs/adrs/0027-simulation-preparedness-and-readiness-gates.md`](docs/adrs/0027-simulation-preparedness-and-readiness-gates.md) - proposed readiness-gate contract for trustworthy automated simulation before simulator-driven evolution is used as primary control signal
- [`docs/adrs/0028-live-shadow-simulation-and-dual-lane-evidence.md`](docs/adrs/0028-live-shadow-simulation-and-dual-lane-evidence.md) - proposed dual-lane simulation model combining deterministic readiness harness signals with advisory live-shadow semantic evidence
- [`specs/contract/README.md`](specs/contract/README.md) - contract package overview and usage model
- [`specs/contract/v1/agent-contract.md`](specs/contract/v1/agent-contract.md) - normative Agent behavior contract (v1)
- [`specs/contract/v1/programs.yaml`](specs/contract/v1/programs.yaml) - abstract generated-program semantic catalog
- [`specs/contract/v1/scenarios.yaml`](specs/contract/v1/scenarios.yaml) - runtime-agnostic conformance scenario set (v1)
- [`specs/contract/v1/tolerant-delegation-profile.md`](specs/contract/v1/tolerant-delegation-profile.md) - tolerant delegation profile contract
- [`specs/contract/v1/tolerant-delegation-scenarios.yaml`](specs/contract/v1/tolerant-delegation-scenarios.yaml) - tolerant delegation scenario suite (v1)
- [`specs/contract/v1/conformance.md`](specs/contract/v1/conformance.md) - runtime harness conformance guidance
- [`specs/contract/v1/recurgent-log-entry.schema.json`](specs/contract/v1/recurgent-log-entry.schema.json) - machine-readable schema for one JSONL observability log entry
- [`specs/contract/v1/recurgent-log-stream.schema.json`](specs/contract/v1/recurgent-log-stream.schema.json) - schema for JSON-array form of the JSONL log stream
- [`specs/contract/v1/simulation-preparedness.contract.yaml`](specs/contract/v1/simulation-preparedness.contract.yaml) - simulation readiness-gate contract and activation policy surface
- [`specs/contract/v1/simulation-run-ledger.schema.json`](specs/contract/v1/simulation-run-ledger.schema.json) - machine-readable schema for simulation run gate-evidence ledger entries
- [`specs/contract/v1/simulation-scenario-pack.schema.json`](specs/contract/v1/simulation-scenario-pack.schema.json) - machine-readable schema for scenario-pack contracts including oracle/scoring/replay fields
- [`specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml`](specs/contract/v1/simulation/scenario-packs/calculator-core-v1.yaml) - class-1 deterministic calculator core simulation pack
- [`specs/contract/v1/simulation/scenario-packs/calculator-edge-v1.yaml`](specs/contract/v1/simulation/scenario-packs/calculator-edge-v1.yaml) - class-1 deterministic calculator edge/error simulation pack
- [`runtimes/ruby/lib/recurgent.rb`](runtimes/ruby/lib/recurgent.rb) - core runtime dispatch, execution, retry, and outcome mapping
- [`runtimes/ruby/lib/recurgent/prompting.rb`](runtimes/ruby/lib/recurgent/prompting.rb) - system/user prompt construction and tool schema
- [`runtimes/ruby/lib/recurgent/observability.rb`](runtimes/ruby/lib/recurgent/observability.rb) - JSONL log composition and debug capture
- [`runtimes/ruby/lib/recurgent/call_execution.rb`](runtimes/ruby/lib/recurgent/call_execution.rb) - dynamic call orchestration and execution-path selection
- [`runtimes/ruby/lib/recurgent/outcome.rb`](runtimes/ruby/lib/recurgent/outcome.rb) - Outcome envelope model and delegation-friendly value proxy behavior
- [`runtimes/ruby/lib/recurgent/providers.rb`](runtimes/ruby/lib/recurgent/providers.rb) - Anthropic/OpenAI provider adapters
- [`runtimes/ruby/spec/recurgent_spec.rb`](runtimes/ruby/spec/recurgent_spec.rb) - core runtime behavior specs (initialization, coordination, persistence, contracts, delegation)
- [`runtimes/ruby/spec/agent/method_calls_spec.rb`](runtimes/ruby/spec/agent/method_calls_spec.rb) - dynamic dispatch and method-call behavior specs
- [`runtimes/ruby/spec/agent/prompt_construction_spec.rb`](runtimes/ruby/spec/agent/prompt_construction_spec.rb) - prompt composition and guardrail prompt contract specs
- [`runtimes/ruby/spec/agent/logging_spec.rb`](runtimes/ruby/spec/agent/logging_spec.rb) - logging and observability field contract specs
- [`runtimes/ruby/spec/agent/providers_spec.rb`](runtimes/ruby/spec/agent/providers_spec.rb) - Anthropic/OpenAI adapter specs
- [`runtimes/ruby/spec/support/agent_spec_shared_context.rb`](runtimes/ruby/spec/support/agent_spec_shared_context.rb) - shared test setup/helpers used by agent spec files
- [`runtimes/ruby/spec/acceptance/recurgent_acceptance_spec.rb`](runtimes/ruby/spec/acceptance/recurgent_acceptance_spec.rb) - deterministic end-to-end acceptance scenarios
- [`runtimes/ruby/examples/`](runtimes/ruby/examples) - executable domain demos for manual verification
- [`runtimes/ruby/examples/observability_demo.rb`](runtimes/ruby/examples/observability_demo.rb) - deterministic tolerant-flow demo with flaky tool for watcher testing
- [`runtimes/ruby/README.md`](runtimes/ruby/README.md) - Ruby runtime-specific commands and structure
- [`runtimes/lua/README.md`](runtimes/lua/README.md) - Lua runtime placeholder contract
- [`bin/recurgent-watch`](bin/recurgent-watch) - runtime-agnostic live JSONL log watcher for delegation trace analysis
- [`.github/workflows/ci.yml`](.github/workflows/ci.yml) - required CI checks for tests and lint
- [`.github/workflows/simulation-readiness-ci.yml`](.github/workflows/simulation-readiness-ci.yml) - class-1 readiness gate workflow evaluating `G0`-`G5` in CI with per-pack artifacts and summaries
- [`.github/workflows/simulation-readiness-nightly.yml`](.github/workflows/simulation-readiness-nightly.yml) - nightly expanded-seed simulation readiness workflow publishing trend artifacts
- [`.github/workflows/security.yml`](.github/workflows/security.yml) - dependency review, bundler-audit, and secret scanning checks
- [`.github/workflows/pr-compliance.yml`](.github/workflows/pr-compliance.yml) - issue-first and PR-template enforcement gate
- [`.github/workflows/stale.yml`](.github/workflows/stale.yml) - stale PR management policy automation
- [`.github/pull_request_template.md`](.github/pull_request_template.md) - required PR structure and contributor acknowledgements
- [`.github/ISSUE_TEMPLATE/bug_report.yml`](.github/ISSUE_TEMPLATE/bug_report.yml) - bug report intake template
- [`.github/ISSUE_TEMPLATE/feature_request.yml`](.github/ISSUE_TEMPLATE/feature_request.yml) - feature intake template
- [`.github/CODEOWNERS`](.github/CODEOWNERS) - default maintainer review ownership
- [`.github/dependabot.yml`](.github/dependabot.yml) - automated dependency update configuration

Index Maintenance Rule:

- Append or update this index whenever adding/renaming key docs, architecture files, or workflows.
- Refresh timestamp at least daily on active development days.
