# Open Source Release Checklist

Status date: 2026-02-18
Scope: repository-level launch readiness for Recurgent (Ruby runtime first, Lua runtime scaffolded)

## 1. Product Positioning and Scope

- [x] README narrative is explicit on project intent (LLM-native Tool Builder/Tool delegation runtime).
- [x] Runtime scope is clear: Ruby is production path, Lua is planned parity path.
- [x] Non-goals are explicit (for example: no hard runtime validation of delegation contracts in current phase).
- [x] Naming language is consistent across docs (Tool Builder, Tool, Delegate, Outcome, Delegation Budget).

## 2. Legal and Policy Baseline

- [x] [`LICENSE`](../LICENSE) present and correct.
- [x] [`CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md) present.
- [x] [`CONTRIBUTING.md`](../CONTRIBUTING.md) present.
- [x] [`SECURITY.md`](../SECURITY.md) present.
- [x] [`SUPPORT.md`](../SUPPORT.md) present.
- [x] Verify copyright and year are correct everywhere.
- [x] Confirm all example snippets are safe to distribute publicly (no proprietary content/API secrets).
- [x] Confirm repository has no trademark-sensitive or third-party restricted assets.

## 3. Repository Hygiene

- [x] Remove accidental local/dev artifacts (scratch files, tmp outputs, local state dumps).
- [x] Ensure `.gitignore` excludes local logs, tokens, generated binaries, and editor artifacts.
- [ ] Confirm no secrets in history and working tree (`gitleaks` clean).
- [x] Ensure no sensitive issue data is left in local tracker exports intended for publish.
- [x] Validate top-level structure is intentional ([`README.md`](../README.md), [`docs/`](.), [`runtimes/`](../runtimes), [`specs/`](../specs), [`bin/`](../bin)).

## 4. Documentation Readiness

- [x] [`README.md`](../README.md) has:
  - [x] clear value proposition
  - [x] quickstart that works
  - [x] minimal runnable example
  - [x] links to docs index and FAQs
- [x] [`docs/index.md`](index.md) links are complete and not stale.
- [x] [`docs/onboarding.md`](onboarding.md) setup steps are reproducible with `mise`.
- [x] [`docs/product-specs/delegation-contracts.md`](product-specs/delegation-contracts.md) matches runtime behavior (symmetry for `Agent.for` and `delegate`).
- [x] [`docs/observability.md`](observability.md) matches emitted JSONL fields (`trace_id`, `call_id`, `contract_source`, etc.).
- [x] [`docs/delegate-vs-for.md`](delegate-vs-for.md) examples reflect current API.
- [x] ADR index includes all active design decisions and no stale statuses.
- [x] Add/verify a concise “Known limitations” section:
  - [x] stdlib-only execution constraints
  - [x] provider may return invalid payloads
  - [x] tolerant outcomes may need caller-side quality checks

## 5. API and Runtime Contract Stability

- [x] `Agent.for(...)` and `delegate(...)` contract interfaces are symmetric and documented.
- [x] Error taxonomy is documented and stable (`provider`, `invalid_code`, `execution`, `timeout`, `budget_exceeded`).
- [x] Capability-boundary prompt rule is present in runtime prompts.
- [x] Logging path normalizes UTF-8 and avoids JSON 3.0 breakage warnings.
- [x] Conformance docs in [`specs/contract/v1/`](../specs/contract/v1) reflect current behavior.

## 6. Quality Gates (Ruby Runtime)

- [x] `mise exec -- bundle exec rspec` passes in [`runtimes/ruby`](../runtimes/ruby).
- [x] `mise exec -- bundle exec rubocop` passes in [`runtimes/ruby`](../runtimes/ruby).
- [x] Deterministic examples run successfully (especially `observability_demo.rb`).
- [x] At least one manual smoke run validates tolerant failure handling for provider-invalid payload.
- [x] Regression coverage exists for:
  - [x] contract merge semantics
  - [x] prompt capability-boundary rules
  - [x] logging metadata (`contract_source`, trace fields)
  - [x] encoding normalization in logs

## 7. CI, Security, and Dependency Automation

- [x] CI workflow present for tests/lint.
- [x] Security workflow present (dependency review, bundler audit, secret scanning).
- [x] Dependabot config present.
- [x] CI required checks are enforced via branch protection.
- [ ] Security scanning alerts are empty or triaged.
- [x] Dependency update policy is documented and operational.

## 8. Community Workflow and Anti-Spam Controls

- [x] Issue templates present.
- [x] PR template present.
- [x] CODEOWNERS present.
- [x] PR compliance workflow present.
- [x] Stale workflow present.
- [x] Maintainer triage playbook includes bot/low-value PR handling criteria.
- [x] PR compliance messaging clearly references [`CONTRIBUTING.md`](../CONTRIBUTING.md) and [`CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md).
- [x] Labels are configured in repo (`ready-for-pr`, `accepted`, `good first issue`, `help wanted`).

## 9. GitHub Repository Settings (Manual)

- [x] Branch protection on `main`:
  - [x] require PR reviews
  - [x] require status checks (`CI`, `PR Compliance`, `Security`)
  - [x] dismiss stale approvals on new commits
  - [x] block force pushes and deletions
- [ ] Enable private vulnerability reporting.
- [x] Set repository description and topics.
- [ ] Enable Discussions (optional, but recommended for usage questions).
- [x] Configure default issue/PR labels and triage permissions.

## 10. Release Artifact and Versioning

- [x] Decide and tag first public version (for example `v0.1.0`).
- [x] Ensure [`CHANGELOG.md`](../CHANGELOG.md) has release notes for initial public release.
- [x] Ensure runtime gem metadata links are valid (`homepage`, `source_code_uri`, `changelog_uri`).
- [x] Confirm release process doc aligns with actual tagging and publishing commands.
- [x] Prepare release notes with:
  - [x] what is stable
  - [x] what is experimental
  - [x] migration notes (if any)

## 11. Launch Day Checklist

- [ ] Run final clean-room setup using onboarding docs.
- [x] Run full tests/lint one final time on clean tree.
- [ ] Verify examples used in README run without manual patching.
- [x] Publish release/tag.
- [ ] Announce with clear expectations and known limitations.
- [ ] Monitor first 24h issues and discussions.

## 12. Post-Launch (First 2 Weeks)

- [ ] Triage incoming issues daily.
- [ ] Classify bug reports into contract/runtime/docs buckets.
- [ ] Tighten docs where user confusion is repeated.
- [ ] Track top failure modes from logs and convert to tests/docs.
- [ ] Create next milestone focused on highest-leverage reliability fixes.

## 13. Future Work Backlog

- [ ] Add generated-code caching layer (cache generated code for repeated role/method/input patterns).
- [ ] Add persistent generated-code layer (store/reuse generated code across sessions to grow software agentically).

## Local Verification Notes

Completed locally on 2026-02-18:

- Runtime checks:
  - `cd runtimes/ruby && bundle exec rspec` (`238 examples, 0 failures`)
  - `cd runtimes/ruby && bundle exec rubocop` (clean)
  - `cd runtimes/ruby && mise exec -- ruby examples/observability_demo.rb` (tolerant failure behavior validated)
- Documentation/link checks:
  - [`docs/index.md`](index.md) file references resolved locally (no missing file paths)
- Hygiene:
  - Purged local [`.beads/`](../.beads) state.
  - Removed generated article artifacts from [`runtimes/ruby/`](../runtimes/ruby).
  - Added ignore rules for generated article outputs in `.gitignore`.
- Security automation notes:
  - GitHub Dependabot vulnerability alerts enabled for the repository.
  - Branch protection enforces required checks: `Ruby test and lint`, `Enforce PR template and issue-first policy`, `bundler-audit`, `gitleaks`.
  - Secret scanning and code scanning still require repository visibility/licensing changes (tracked in Section 9 and Section 7).
  - `v0.1.0` tag and release published: `https://github.com/kulesh/recurgent/releases/tag/v0.1.0`.

## Suggested Operating Rule

Use this checklist as a gate: launch when sections 1–8 are complete and section 9 has no open critical settings.
