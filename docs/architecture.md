# Runtime Architecture

This document is the canonical architecture map for the current Ruby runtime (`runtimes/ruby`).

It reflects the implemented model across:

1. Tool Builder / Tool / Worker execution roles.
2. Cross-session persistence and cacheability-gated artifact reuse.
3. Contract validation, tolerant outcomes, pattern memory, and dual-lane evolution.

## Component Map

```mermaid
flowchart LR
  Caller[Caller Code] --> Agent[Agent method_missing]
  Agent --> Prompt[Prompting]
  Prompt --> Provider[Provider Adapter]
  Provider --> Program[GeneratedProgram]

  Program --> Selector[Artifact Selector]
  Selector -->|artifact hit + eligible| Persisted[Persisted Execution]
  Selector -->|miss / stale / non-cacheable| Fresh[Fresh Generation Path]

  Persisted --> Exec[Execution]
  Fresh --> Exec

  Exec -->|no deps| Inline[Inline Eval]
  Exec -->|deps declared| WorkerExec[Worker Executor]
  WorkerExec --> Worker[Worker Process]

  Inline --> Outcome[Outcome]
  Worker --> Outcome

  Outcome --> Validator[Outcome Contract Validator]
  Validator --> Observability[Observability JSONL]
  Validator --> Metrics[Artifact Metrics]
  Validator --> Pattern[Pattern Memory Store]

  Metrics --> ArtifactStore[Artifact Store]
  Metrics --> ToolStore[Tool Store]
  Pattern --> Prompt
  ToolStore --> Prompt
```

## Top-Level Call Flow

```mermaid
sequenceDiagram
  participant C as Caller
  participant A as Agent
  participant P as Provider
  participant S as ArtifactSelector
  participant X as Executor
  participant W as Worker
  participant V as ContractValidator
  participant O as Observability

  C->>A: method_missing(method, args, kwargs)
  A->>S: select(role, method_name, args, contract)
  alt Eligible persisted artifact
    S-->>A: artifact code
  else Miss / stale / non-cacheable
    A->>P: generate_program(system_prompt, user_prompt)
    P-->>A: GeneratedProgram(code, dependencies)
  end

  A->>X: execute(code, dependencies)
  alt dependencies empty
    X->>A: eval in binding
  else dependencies present
    X->>W: execute via JSON IPC
    W-->>X: value + context snapshot
  end

  X-->>A: Outcome
  A->>V: validate delegated deliverable/acceptance
  V-->>A: normalized Outcome
  A->>O: write trace + telemetry
  A-->>C: Outcome
```

## Artifact Reuse and Repair Policy

```mermaid
flowchart TD
  Start[role + method] --> Load[Load Artifact]
  Load --> Missing{artifact exists?}
  Missing -- no --> Generate[Generate New Program]
  Missing -- yes --> Eligible{cacheable and healthy?}
  Eligible -- no --> Generate
  Eligible -- yes --> Run[Execute Artifact]
  Run --> ExecOK{execution ok?}
  ExecOK -- yes --> Keep[Record success + keep artifact]
  ExecOK -- no --> FailureClass{failure class}
  FailureClass -->|extrinsic| Retry[Retry or defer]
  FailureClass -->|intrinsic/adaptive| Repair[Repair artifact]
  Repair --> RepairOK{repair succeeds?}
  RepairOK -- yes --> Promote[Promote repaired artifact]
  RepairOK -- no --> Regenerate[Full regenerate]
  Generate --> Persist[Persist new artifact]
  Regenerate --> Persist
  Keep --> End[Return Outcome]
  Retry --> End
  Promote --> End
  Persist --> End
```

## Dual-Lane Evolution Model

```mermaid
flowchart LR
  subgraph InlineLane[Inline Lane: hot path]
    Call[Tool Call] --> ShapeCheck[Deliverable Shape Validation]
    ShapeCheck --> Typed[Typed Outcome]
    Typed --> Referral{wrong_tool_boundary?}
    Typed --> Utility{low_utility?}
  end

  subgraph OOBLane[Out-of-Band Lane: reflective path]
    Telemetry[Telemetry + Traces] --> Cohesion[Cohesion Analysis]
    Telemetry --> Corrections[user_correction Signals]
    Cohesion --> Recs[Recommendations]
    Corrections --> Recs
  end

  Referral --> Telemetry
  Utility --> Telemetry
  Recs --> KnownTools[known_tools Health Injection]
  KnownTools --> ToolBuilder[Tool Builder Decisions]
```

## Key Runtime Boundaries

1. `runtimes/ruby/lib/recurgent.rb` is the entry boundary for dynamic dispatch and runtime orchestration.
2. `runtimes/ruby/lib/recurgent/persisted_execution.rb` and `runtimes/ruby/lib/recurgent/artifact_selector.rb` own persisted-vs-fresh execution decisions.
3. `runtimes/ruby/lib/recurgent/outcome_contract_validator.rb` is the delegated contract boundary (`deliverable`, `acceptance`).
4. `runtimes/ruby/lib/recurgent/tool_store.rb` and `runtimes/ruby/lib/recurgent/artifact_store.rb` own cross-session state.
5. `runtimes/ruby/lib/recurgent/pattern_memory_store.rb` and `runtimes/ruby/lib/recurgent/user_correction_signals.rb` feed promotion/evolution signals.
6. `runtimes/ruby/lib/recurgent/tool_maintenance.rb` owns out-of-band maintenance and recommendation workflows.
