# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

## [0.1.0] - 2026-02-13

### Added

- Multi-runtime repository layout with active Ruby runtime and Lua placeholder.
- Canonical `Agent` coordination primitives (`for`, `remember`, `memory`, `delegate`).
- Tolerant dynamic-call contract using `Agent::Outcome`.
- Provider abstraction for Anthropic/OpenAI routing.
- Retry and logging telemetry for generated code execution.
- Contract specification package under `specs/contract/v1`.
- Documentation set: onboarding, ADRs, ubiquitous language, tolerant delegation guidance.

### Changed

- Hard-cut naming transition from `Actuator` terminology to `Recurgent` project + `Agent` operational object.
- Delegation language standardized to Solver/Specialist/Outcome vocabulary.

### Notes

- First public open-source baseline release.
