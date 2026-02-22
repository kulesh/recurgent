# Runtime Architecture

This document is the canonical architecture map for the current Ruby runtime ([`runtimes/ruby`](../runtimes/ruby)).

It reflects the implemented system after the recent lifecycle and boundary hardening work:

1. Tool Builder / Tool / Worker execution gradient.
2. Fresh-generation lifecycle with validation-first retries and transactional rollback.
3. Cross-session tool/artifact persistence with cacheability gating.
4. Delegated outcome contract validation and tolerant interface handling.
5. Structured conversation history, pattern memory, and user-correction signals.
6. Guardrail exhaustion boundary normalization and failed-attempt telemetry capture.

## Architectural Intent

Recurgent is designed for reliable emergence:

- Generate behavior at call time.
- Preserve useful behavior across sessions.
- Detect and repair brittle behavior.
- Keep user-facing boundaries honest and typed.

## System Model

### Role Gradient

1. Tool Builder (depth 0): decides when to Do, Shape, Forge, Orchestrate.
2. Tool (depth 1): executes delegated contract work with bounded scope.
3. Worker (depth >= 2): direct execution, minimal decomposition overhead.

### Runtime Principles

1. Agent-first runtime surface (`method_missing` dispatch).
2. Tolerant interfaces at boundaries (symbol/string key tolerance, typed outcomes).
3. Validation before execution retries.
4. Observability as a first-class runtime product.

### Dynamic Dispatch Boundary (Ruby)

`method_missing` is the dynamic call boundary. Calls bypass dynamic generation when method names are explicitly defined on `Agent`.

Current explicit `Agent` method surface:

- `tool`
- `delegate`
- `remember`
- `runtime_context`
- `to_s`
- `inspect`
- `define_singleton_method` (guardrail)

Execution-wrapper locals for generated code:

- `context` is the canonical mutable state surface.
- `memory` is a local alias to `context` in execution wrappers (sandbox + worker) to absorb model priors without adding host method collisions.

Design invariant:

- Keep public `Agent` method surface narrow; preserve dynamic namespace for emergent domain methods.

## Component Map

```mermaid
flowchart LR
  Caller[Caller Code] --> Dispatch[Agent method_missing]
  Dispatch --> Prompt[Prompting]
  Dispatch --> CallExec[CallExecution]

  CallExec --> Selector[ArtifactSelector]
  Selector -->|eligible artifact| Persisted[PersistedExecution]
  Selector -->|miss / stale / non-cacheable| Fresh[FreshGeneration]

  Fresh --> Provider[Provider Adapter]
  Provider --> Program[GeneratedProgram]
  Fresh --> Guardrail[GuardrailPolicy + Code Checks]
  Fresh --> Retry[Guardrail / Execution / Outcome Retry Lanes]

  Persisted --> Execute[Execution]
  Fresh --> Execute
  Execute -->|no deps| Sandbox[ExecutionSandbox]
  Execute -->|deps| Worker[WorkerExecution]

  Sandbox --> Outcome[Outcome]
  Worker --> Outcome
  Outcome --> Contract[OutcomeContractValidator]
  Contract --> Boundary[GuardrailBoundaryNormalization]

  Boundary --> History[ConversationHistory]
  Boundary --> Pattern[PatternMemoryStore]
  Boundary --> ArtifactStore[ArtifactStore]
  Boundary --> ToolStore[ToolStore]
  Boundary --> Obs[Observability JSONL]
```

## Dynamic Call Lifecycle

```mermaid
sequenceDiagram
  participant C as Caller
  participant A as Agent
  participant S as ArtifactSelector
  participant P as Provider
  participant X as Executor
  participant V as ContractValidator
  participant O as Observability

  C->>A: method_missing(method,args,kwargs)
  A->>S: select persisted artifact
  alt persisted artifact eligible
    S-->>A: artifact code
    A->>X: execute persisted
  else fresh generation
    A->>P: generate_program(system,user,schema)
    P-->>A: code+dependencies
    A->>X: validate+execute fresh attempt
    alt recoverable failure
      X-->>A: retry feedback (guardrail/execution/outcome)
      A->>P: regenerate with feedback
    end
  end
  X-->>A: Outcome
  A->>V: validate delegated deliverable/acceptance
  V-->>A: normalized Outcome
  A->>A: append conversation history + pattern event
  A->>A: persist artifact/tool metrics
  A->>O: write trace log
  A-->>C: Outcome
```

## Fresh Generation Lifecycle (Validation-First)

```mermaid
flowchart TD
  Start[Fresh call] --> Generate[Generate program]
  Generate --> Validate[Static guardrail validation]
  Validate -->|guardrail violation| GRetry{guardrail budget left?}
  GRetry -->|yes| RegenerateG[Inject guardrail feedback + regenerate]
  RegenerateG --> Generate
  GRetry -->|no| GExhaust[GuardrailRetryExhaustedError]

  Validate --> Execute[Execute program]
  Execute -->|runtime exception| ERetry{execution repair budget left?}
  ERetry -->|yes| RegenerateE[Inject execution feedback + regenerate]
  RegenerateE --> Generate
  ERetry -->|no| EFail[Raise execution error]

  Execute --> OutcomePolicy[Validate outcome policy]
  OutcomePolicy -->|retriable non-ok outcome| ORetry{outcome repair budget left?}
  ORetry -->|yes| RegenerateO[Inject outcome feedback + regenerate]
  RegenerateO --> Generate
  ORetry -->|no| OExhaust[OutcomeRepairRetryExhaustedError]

  OutcomePolicy --> Contract[Delegated contract validation]
  Contract --> Success[Return Outcome]
```

## Persistence and Selection

### Tool Registry (`ToolStore`)

- Persists delegated tool metadata (`purpose`, `methods`, `deliverable`, `acceptance`, counters).
- Hydrates `context[:tools]` on startup.
- Tracks usage/success/failure counts.

### Method Artifact Store (`ArtifactStore`)

- Persists generated code per `role + method`.
- Stores:
  - checksum, prompt/runtime versions, dependencies,
  - cacheability metadata,
  - success/failure metrics and rates,
  - generation history (bounded),
  - trigger diagnostics (stage/class/message/attempt_id) for failed-attempt provenance.

### Selection (`ArtifactSelector`)

Artifact executes only when:

1. Cacheability policy allows reuse.
2. Runtime version compatibility holds.
3. Contract fingerprint matches.
4. Code checksum is valid.
5. Artifact is not degraded by health policy.

Otherwise runtime falls back to fresh generation.

## Boundary Semantics

### Delegated Outcome Contract Boundary

`OutcomeContractValidator` enforces delegated `deliverable` shape on successful delegated outcomes.

- Tolerant key semantics (symbol/string).
- Shape mismatch converts to typed `contract_violation` outcome.
- Validation state is captured in call telemetry fields.

### Guardrail Exhaustion User Boundary

`GuardrailBoundaryNormalization` normalizes top-level exhausted guardrail failures:

- Internal subtype/metadata is preserved.
- User-facing message is stabilized:
  - `"This request couldn't be completed after multiple attempts."`

### Source/Provenance Boundary

`ConversationHistory` stores compact source refs in `outcome_summary` when provenance is present:

- `source_count`
- `primary_uri`
- `retrieval_mode`

This supports source follow-up behavior without preloading full prior records into prompts.

## Conversation and Pattern Memory

### Structured Conversation History

Each call appends one canonical record with:

- call identity (`trace_id`, `call_id`, `parent_call_id`, `depth`)
- method invocation (`method_name`, `args`, `kwargs`)
- compact `outcome_summary`
- timing (`duration_ms`, timestamp)

### Pattern Memory

`PatternMemoryStore` records capability-pattern events for generated/repaired calls and tracks user-correction signals.

Used to inject recent pattern summaries back into prompting at depth 0.

## Observability Model

JSONL log entries include:

1. Invocation identity and timing.
2. Program source (`generated`, `persisted`, `repaired`) and dependencies.
3. Contract validation fields.
4. Retry-lane counters:
  - `guardrail_recovery_attempts`
  - `execution_repair_attempts`
  - `outcome_repair_attempts`
5. Attempt failure telemetry:
  - `attempt_failures[]`
  - `latest_failure_stage/class/message`
6. Cacheability and artifact-hit metadata.
7. Optional debug envelope (prompts/context/error backtrace) when debug is enabled.

## Module Composition Map

The runtime is organized into ~50 modules mixed into a single `Agent` class. This diagram groups them into functional clusters with primary dependency edges. Start here to locate which module owns a subsystem.

```mermaid
flowchart TB
  subgraph Core["Core Dispatch"]
    Agent["Agent (entry)"]
    CE[CallExecution]
    CS[CallState]
    OC[Outcome]
  end

  subgraph Exec["Execution Paths"]
    PE[PersistedExecution]
    FG[FreshGeneration]
    ES[ExecutionSandbox]
    WE[WorkerExecution]
    WS[WorkerSupervisor]
  end

  subgraph ToolEvo["Tool Evolution"]
    AS[ArtifactStore]
    ASel[ArtifactSelector]
    AR[ArtifactRepair]
    AM[ArtifactMetrics]
  end

  subgraph Valid["Validation"]
    GP[GuardrailPolicy]
    GCC[GuardrailCodeChecks]
    GOF[GuardrailOutcomeFeedback]
    GBN[GuardrailBoundaryNormalization]
    FOR[FreshOutcomeRepair]
    OCV[OutcomeContractValidator]
  end

  subgraph RoleProf["Role Profiles"]
    RP[RoleProfile]
    RPR[RoleProfileRegistry]
    RPG[RoleProfileGuard]
    Auth[Authority]
  end

  subgraph Gov["Governance"]
    DI[DelegationIntent]
    DO[DelegationOptions]
    TRI[ToolRegistryIntegrity]
    PS[ProposalStore]
  end

  subgraph MemContent["Memory & Content"]
    CH[ConversationHistory]
    CHN[ConversationHistoryNormalization]
    CSt[ContentStore]
    PMS[PatternMemoryStore]
    UCS[UserCorrectionSignals]
    CPE[CapabilityPatternExtractor]
  end

  subgraph Obs["Observability"]
    Ob[Observability]
    OHF[ObservabilityHistoryFields]
    OAF[ObservabilityAttemptFields]
    AI[AttemptIsolation]
    AFT[AttemptFailureTelemetry]
  end

  subgraph DepWork["Dependencies & Workers"]
    Dep[Dependencies]
    DM[DependencyManifest]
    EM[EnvironmentManager]
    WEnt[WorkerEntrypoint]
    PT[PreparationTicket]
  end

  subgraph Sim["Simulation"]
    SR[SimulationRunner]
    SPC[SimulationPackContract]
    SSP[SimulationScenarioPack]
    SFS[SimulationFixtureStore]
    SRL[SimulationRunLedger]
    SS[SimulationScorer]
    SCO[SimulationCalculatorOracle]
  end

  Agent --> CE
  CE --> PE & FG
  PE --> ASel & AR
  FG --> GP & FOR
  CE --> ES & WE
  WE --> WS
  AS --> AM
  ASel --> AM
  CE --> OCV --> RPG
  FG --> Dep --> EM
  CE --> CH --> CSt
  CE --> PMS
  CE --> AS
  CE --> Ob
  SR --> SSP & SFS & SRL & SS & SCO
```

- `Agent` is the single host class; all other boxes are `include`d modules or standalone classes.
- Arrows show "calls into" at runtime, not Ruby inheritance.
- `SimulationRunner` is a standalone class instantiated outside normal dispatch.

## Full Dispatch Pipeline

Extends the [Dynamic Call Lifecycle](#dynamic-call-lifecycle) with subsystems omitted from that sequence: call frame setup, state initialization, artifact selection with lifecycle awareness, the sandbox/worker execution fork, contract and role profile validation, and all post-call persistence steps.

```mermaid
sequenceDiagram
  participant C as Caller
  participant A as Agent.method_missing
  participant F as CallFrame
  participant S as CallState
  participant PR as Prompting
  participant SEL as ArtifactSelector
  participant REP as ArtifactRepair
  participant P as Provider
  participant GP as GeneratedProgram
  participant GR as GuardrailPolicy
  participant SB as ExecutionSandbox
  participant WK as WorkerExecution
  participant CV as OutcomeContractValidator
  participant RPG as RoleProfileGuard
  participant CH as ConversationHistory
  participant CS as ContentStore
  participant PM as PatternMemoryStore
  participant AS as ArtifactStore
  participant OB as Observability

  C->>A: method_call(name, args, kwargs)
  A->>F: _with_call_frame (trace_id, call_id, depth)
  A->>S: _initial_call_state (60+ fields)
  A->>S: _capture_solver_shape_state!
  A->>S: _capture_awareness_state!

  A->>PR: _build_system_prompt + _build_user_prompt

  A->>SEL: _select_persisted_artifact
  alt persisted artifact eligible
    SEL-->>A: artifact (with lifecycle_state)
    A->>S: _capture_persisted_artifact_state!
  else artifact repair needed
    SEL-->>A: nil
    A->>REP: _repair_persisted_artifact
    REP-->>A: repaired code or nil
  else fresh generation
    A->>P: generate_program(system, user, schema)
    P-->>A: code + dependencies
    A->>GP: parse + validate syntax
    A->>GR: _validate_generated_code_policy!
    alt guardrail violation
      GR-->>A: ToolRegistryViolationError
      A->>A: retry with guardrail feedback (budget)
    end
  end

  alt no dependencies
    A->>SB: _execute_code(code, binding)
  else has dependencies
    A->>WK: _execute_in_worker(env, code, payload)
  end

  A->>CV: _validate_delegated_outcome_contract
  CV-->>A: normalized Outcome (or contract_violation)
  A->>RPG: _evaluate_role_profile_continuity!
  RPG-->>A: compliance report (shadow or enforced)

  par Post-call persistence
    A->>CH: _append_conversation_history_record!
    CH->>CS: write content entry (if eligible)
    A->>PM: _record_pattern_memory_event
    A->>AS: _persist_method_artifact_for_call
    AS->>AS: _artifact_evaluate_promotion_shadow!
    A->>OB: _log_dynamic_call (JSONL)
  end

  A->>S: _finalize_solver_shape_state!
  A->>S: _finalize_awareness_state!
  A-->>C: Outcome
```

- `_with_call_frame` establishes `trace_id` / `call_id` / `parent_call_id` linkage for the full call tree.
- Post-call persistence runs in `ensure` — it executes even when the call raises.
- `_capture_solver_shape_state!` and `_capture_awareness_state!` bookend the call, running both pre- and post-execution.

## Artifact Promotion State Machine

Artifacts progress through a lifecycle that gates when persisted code becomes the preferred execution path. Promotion decisions are evaluated in shadow mode first; enforcement is opt-in via `promotion_enforcement_enabled`.

```mermaid
stateDiagram-v2
  [*] --> candidate: initial forge

  candidate --> probation: first successful outcome

  probation --> durable: promote\n(all gates pass)
  probation --> degraded: degrade\n(regression detected)
  probation --> probation: continue_probation\n(gates not yet met)

  durable --> durable: hold\n(healthy)
  durable --> degraded: degrade\n(regression detected)

  degraded --> durable: promote\n(recovery — all gates pass)
  degraded --> degraded: hold\n(still regressed)

  note right of probation
    Promotion gates:
    min_calls ≥ 10
    min_sessions ≥ 2
    contract_pass_rate ≥ 0.95
    role_profile_pass_rate ≥ 0.99
    guardrail/outcome exhaustions = 0
    wrong_boundary_count = 0
    provenance_violations = 0
    state_key_consistency ≥ 0.5
    candidate ≥ incumbent contract rate
  end note

  note left of degraded
    Regression trigger:
    calls ≥ 3 AND
    failure_rate > 0.6 AND
    failures > successes
  end note
```

- Legacy artifacts (pre-lifecycle) enter at `probation` instead of `candidate` to avoid cold-start regressions.
- `degraded` artifacts are skipped by `ArtifactSelector`; the runtime falls through to fresh generation.
- The shadow ledger records every promotion evaluation for offline analysis.

## Delegation and Depth Gradient

Each `delegate()` call spawns a child `Agent` at `depth + 1` with decremented budgets. The available stances narrow as depth increases, preventing unbounded decomposition.

```mermaid
flowchart TD
  subgraph D0["Depth 0 — Tool Builder"]
    TB[Agent.for role]
    TB_S["Stances: Do, Shape, Forge, Orchestrate"]
    TB_D["delegate → creates child at depth 1"]
  end

  subgraph D1["Depth 1 — Tool"]
    T[Agent.for child_role]
    T_S["Stances: Do, Shape"]
    T_D["delegate → creates child at depth 2"]
    T_C["Bound by: deliverable + acceptance contract"]
  end

  subgraph D2["Depth 2+ — Worker"]
    W[Agent.for worker_role]
    W_S["Stances: Do only"]
    W_N["No further delegation"]
    W_E["Direct execution, minimal overhead"]
  end

  D0 -->|"delegate(role, contract)"| D1
  D1 -->|"delegate(role, contract)"| D2

  subgraph Inherited["Inherited Settings"]
    IS["model, verbose, log, debug\nbudgets, trace_id"]
  end

  Inherited -.->|"via _inherited_settings"| D1
  Inherited -.->|"via _inherited_settings"| D2
```

- Budget fields (guardrail retries, execution repair, outcome repair) are decremented at each depth level.
- `trace_id` is inherited so the full delegation tree shares one trace.
- At depth 0, `_solver_shape_stance` returns `"shape"` for undelegated calls and `"forge"` for dynamic dispatch methods.

## Role Profile Guard Pipeline

After code executes and the outcome contract is validated, the role profile guard checks behavioral continuity across sibling methods. It operates in shadow mode by default (log-only); enforcement is opt-in.

```mermaid
flowchart TD
  Start["Code executed, Outcome validated"] --> HasProfile{Active role\nprofile?}
  HasProfile -->|No| Skip["Skip — return Outcome unchanged"]
  HasProfile -->|Yes| Constraints["Find constraints matching method"]

  Constraints --> Scope{"Scope\nresolution"}
  Scope -->|all_methods| AllMethods["Expand to all observed methods\n(minus exclusions)"]
  Scope -->|explicit_methods| ExplicitMethods["Use declared method list"]

  AllMethods --> Gather
  ExplicitMethods --> Gather

  Gather["Gather observations per constraint kind"]
  Gather --> SSK["shared_state_slot:\nprimary context[] write key"]
  Gather --> RSF["return_shape_family:\nvalue shape (hash:keys, array, numeric, …)"]
  Gather --> SF["signature_family:\nargs[n] + kwargs[k] pattern"]

  SSK & RSF & SF --> Mode{"Evaluation\nmode"}

  Mode -->|coordination| Coord["All observations\nmust be identical"]
  Mode -->|prescriptive| Presc["All observations must\nmatch canonical value"]

  Coord & Presc --> Result{Passed?}
  Result -->|Yes| Pass["Record compliance in CallState"]
  Result -->|No, shadow mode| Shadow["Log violation + correction hint\nReturn Outcome unchanged"]
  Result -->|No, enforced| Fail["Raise ToolRegistryViolationError\nwith correction hint"]
```

- Observations are cached per-session in `@role_profile_observation_cache` so sibling methods accumulate context across calls.
- Scorecard `role_profile_pass_rate` feeds the artifact promotion gate (`≥ 0.99` required).
- Constraint kinds can be extended without changing the guard pipeline — add a new `when` branch in `_role_profile_constraint_observations`.

## Simulation Gate Pipeline

The simulation subsystem validates runtime behavior through deterministic fixture replay and live-shadow execution. Results pass through a 6-gate readiness evaluation before being recorded in the run ledger.

```mermaid
flowchart LR
  Pack["Scenario Pack\n(YAML/JSON)"] --> Validate["SimulationPackContract\nschema validation"]
  Validate --> Lane{"Execution\nlane"}

  Lane -->|deterministic| Det["Fixture-based replay\n(SimulationFixtureStore)"]
  Lane -->|live_shadow| Live["Live Agent execution\n(SimulationRunScope)"]

  Det --> Oracle["Oracle evaluation\n(SimulationCalculatorOracle)"]
  Live --> Oracle

  Oracle --> Score["SimulationScorer\nweighted score vector"]
  Score --> Trace["SimulationTraceSchemaValidator\ntrace log validation"]
  Trace --> Diff["SimulationBaselineDiff\ncompare to prior run"]

  Diff --> Gates["Gate evaluation"]

  subgraph GateEval["G0–G5 Gates"]
    G0["G0: Pack contract valid"]
    G1["G1: Replay stability ≥ 0.99"]
    G2["G2: Score vector reproducible"]
    G3["G3: Trace schema valid"]
    G4["G4: Baseline diff classified"]
    G5["G5: Operational readiness\n(ci / nightly)"]
  end

  Gates --> G0 & G1 & G2 & G3 & G4 & G5

  G0 & G1 & G2 & G3 & G4 & G5 --> Ledger["SimulationRunLedger\nappend entry"]

  Ledger --> Window["SimulationStabilizationWindow\ntrack convergence"]
  Window --> Advisory["SimulationAdvisoryStatus\nreadiness signal"]
```

- Deterministic lane uses seeded oracle evaluation against fixture snapshots; live-shadow lane creates real `Agent` instances and executes scenario scripts.
- Gate statuses are `pass`, `fail`, `advisory`, or `not_applicable` — advisory gates log measurements without blocking.
- The stabilization window and advisory status modules consume ledger history to determine trend-based readiness.

## Data Transform Journey

Traces the shape of data as it flows through the dispatch pipeline, from caller input to final persisted outputs.

```mermaid
flowchart TD
  Input["Input\n(method_name, args, kwargs)"]
  Input --> Frame["Call Frame\n{trace_id, call_id,\nparent_call_id, depth}"]
  Frame --> State["CallState\n(60+ telemetry fields:\nprogram_source, cacheable,\nlifecycle_state, attempt_id, …)"]

  State --> Prompts["Prompts\n{system_prompt, user_prompt}\n(depth-aware, pattern-injected,\ncontract-scoped)"]
  Prompts --> Provider["Provider Call\n{model, system, user, tool_schema}\n→ Anthropic or OpenAI API"]

  Provider --> Program["GeneratedProgram\n{code, dependencies[],\nnormalized_dependencies[]}"]
  Program --> ExecInput["Execution Input\n{code, binding, context,\nargs, kwargs, Agent class}"]

  ExecInput --> RawResult["Raw Result\n(any Ruby value from eval)"]
  RawResult --> Coerced["Outcome\n{status, value, error_type,\nerror_message, retriable,\ntool_role, method_name}"]

  Coerced --> ContractVal["Contract-Validated Outcome\n+ contract_validation_applied\n+ contract_validation_passed\n+ expected/actual keys"]

  ContractVal --> ProfileVal["Profile-Evaluated Outcome\n+ role_profile_compliance\n+ violation_count/types\n+ correction_hint"]

  ProfileVal --> Outputs

  subgraph Outputs["Persisted Outputs"]
    History["History Record\n{call_id, method, args,\noutcome_summary, duration_ms}"]
    Content["Content Entry\n{ref, kind, bytes,\ndigest, eviction_count}"]
    Pattern["Pattern Event\n{capability_patterns[],\nevidence, correction signals}"]
    Artifact["Artifact Persist\n{code, checksum, metrics,\nlifecycle, scorecards,\ngeneration history}"]
    Log["JSONL Log Entry\n{identity, timing, source,\nretry counters, attempt failures,\ncacheability, debug envelope}"]
  end

  ProfileVal --> History
  ProfileVal --> Content
  ProfileVal --> Pattern
  ProfileVal --> Artifact
  ProfileVal --> Log
```

- `CallState` is the mutable accumulator — every subsystem writes its telemetry fields into it during dispatch.
- `Outcome.coerce` normalizes arbitrary Ruby return values into the typed `Outcome` wrapper before any validation runs.
- The five output sinks run in `ensure`, so they capture data even when the call raises an exception.

## Runtime Data Surfaces

Primary persisted files under toolstore root:

- `registry.json` - tool registry metadata
- `patterns.json` - pattern-memory events
- `artifacts/<role>/<method>.json` - per-method code artifact

Path defaults are XDG-compliant through runtime config.

## Current Boundaries of This Document

This document describes implemented runtime behavior.

For rationale and tradeoffs:

- see [`docs/adrs/`](adrs).

For phased execution detail:

- see [`docs/plans/`](plans).
