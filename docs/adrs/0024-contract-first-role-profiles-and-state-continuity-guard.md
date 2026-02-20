# ADR 0024: Contract-First Role Profiles and State Continuity Guard

- Status: proposed
- Date: 2026-02-19

## Context

ADR 0023 introduced solver-shape observability and reliability-gated lifecycle promotion. That infrastructure answers "how reliably did this artifact execute?" It does not answer "is this role semantically coherent across methods?"

ADR 0025 is now implemented and adds the control-plane substrate for awareness, proposal artifacts, and authority gating. ADR 0024 must run on top of that substrate:

1. role-profile mutations are proposal artifacts (`role_profile_update`),
2. enactment is maintainer-approved (`approve`/`apply`) and authority-gated,
3. observability fields from ADR 0025 are available for continuity rollout evidence.

That distinction is now explicit:

1. reliability infrastructure ranks observed behavior,
2. role contracts define correctness for shared-state method families.

For standalone tools (for example `web_fetcher.fetch_url`) reliability metrics are often sufficient because method scope is self-contained. For roles with sibling methods that share memory/state (for example calculator, personal assistant memory operations, debate moderation state), reliability metrics alone are insufficient:

1. two methods can both "succeed" while writing different state keys,
2. signatures can drift while call outcomes still look structurally valid,
3. return shapes can drift and leak interface instability to callers.

This creates a known gap: promotion can prefer a reliable artifact that is semantically inconsistent with the intended role contract.

It also creates a second risk if contracts are written too prescriptively: profiles can become an evolutionary ceiling. The environment should shape convergence and coherence by default, while allowing explicit deterministic constraints where required.

## Problem Illustration

### Current State: Reliability Can Mask Role Drift

Current generated artifacts can remain operational even when sibling methods disagree on state keys.

```ruby
# generated artifact A (memory setter)
current = context[:memory] || 0
context[:memory] = args[0]
result = context[:memory]

# generated artifact B (add)
current = context[:value] || 0
context[:value] = current + args[0].to_f
result = context[:value]
```

Both methods may produce `ok` outcomes. ADR 0023 scorecards can still show strong reliability, but the role has continuity drift (`:memory` vs `:value`).

### Over-Prescriptive Failure Mode

If profile enforcement always requires one fixed key, coherent evolution can be blocked:

```ruby
# All sibling methods converge on :accumulator
context[:accumulator] = (context[:accumulator] || 0) + args[0].to_f
result = context[:accumulator]
```

This is coherent behavior. It should not fail unless the profile explicitly chooses deterministic key pinning.

### Desired State: Continuity Is Explicit, With Mode-Based Constraints

```ruby
calculator_profile = Agent::RoleProfile.new(
  role: "calculator",
  version: 1,
  constraints: {
    accumulator_slot: {
      kind: :shared_state_slot,
      scope: :all_methods,
      mode: :coordination
    },
    arithmetic_shape: {
      kind: :return_shape_family,
      scope: :all_methods,
      exclude_methods: %w[history],
      mode: :coordination
    }
  }
)
```

Optional strict pinning is supported per constraint when deterministic behavior is required:

```ruby
strict_profile = calculator_profile.with_constraints(
  accumulator_slot: {
    kind: :shared_state_slot,
    scope: :all_methods,
    mode: :prescriptive,
    canonical_key: :value
  }
)
```

## Decision

Introduce an explicit, opt-in role contract layer (`RoleProfile`) and a `State Continuity Guard` that validates role coherence using existing retry/repair infrastructure.

This ADR remains the semantic-coherence layer. ADR 0025 remains the awareness/authority layer.

### 1. Role Profiles Are Explicit and Opt-In

Role profiles are never inferred automatically by runtime category heuristics.

1. profiles are authored by users/maintainers, or
2. proposed by out-of-band evolution tooling and explicitly accepted.

No implicit runtime guessing of "which agents are roles" is introduced.

### 2. Role Profile Uses Constraint Modes (Coordination First)

`RoleProfile` is a correctness contract for role-like interfaces with shared state and multi-method coherence expectations.

V1 profile fields:

1. constraint groups over role behavior,
2. constraint mode per group (`coordination` default, `prescriptive` optional),
3. constraint scope (`all_methods` default; narrowing optional),
4. optional explicit canonical values for prescriptive groups,
5. profile version.

Scope semantics:

1. `scope: :all_methods` (default): any method forged on this role is part of the constraint unless explicitly excluded.
2. `scope: :explicit_methods`: apply only to listed `methods`.
3. `exclude_methods`: optional carve-out list for `all_methods` scope.

This keeps the role contract emergent by default. New methods are included automatically and inherit coordination pressure without predeclaring method names.

### 2a. Clean Break on Schema Shape

This amendment intentionally removes methods-first constraints as the baseline contract shape. Runtime and examples move to scope-first semantics without backward compatibility shims.

1. old profiles that rely on implicit/required `methods` lists must be rewritten,
2. runtime loaders fail fast on unsupported shape,
3. persisted legacy profile artifacts are cleaned or replaced during rollout.

Reliability scorecards remain independent and continue to drive lifecycle ranking/promotion decisions.

Constraint semantics:

1. `coordination`: enforce agreement/coherence across methods; do not enforce one preselected key/shape value.
2. `prescriptive`: enforce explicit declared value (`canonical_key`, exact return shape, required method contract).

### 3. Active Profile Version Is Part of the Contract

Each call binds to one explicit active profile version. Version bumps are deliberate acts.

1. runtime records active version in observability,
2. continuity checks evaluate against that version only,
3. profile upgrades require explicit profile publication/selection.

```ruby
active_profile = role_profile_registry.fetch(role: @role, version: requested_version || :latest)
state.role_profile_version = active_profile.version
```

### 4. Add State Continuity Guard to Existing Contract Lanes

The continuity guard runs as part of existing validation/repair flow (ADR 0014, ADR 0016), not a new enforcement subsystem.

Guard checks:

1. generated code and outcomes satisfy each active profile constraint,
2. coordination constraints validate sibling agreement across observed role methods in scope,
3. prescriptive constraints validate explicit declared values.

Violation handling:

1. emit typed recoverable contract violation (`role_profile_continuity_violation`),
2. provide deterministic correction hint (agreement hint for coordination, canonical value hint for prescriptive),
3. retry through existing recoverable regeneration budget,
4. preserve full diagnostics in observability.

```ruby
def _enforce_role_profile_continuity!(profile:, method_name:, generated_code:, outcome:)
  return unless profile

  report = RoleProfileGuard.evaluate(
    profile: profile,
    method_name: method_name,
    code: generated_code,
    outcome: outcome
  )
  return if report.ok?

  raise RecoverableGuardrailViolation.new(
    "role_profile_continuity_violation",
    correction: report.correction_hint
  )
end
```

```ruby
def _evaluate_constraint(constraint, observations)
  case constraint[:mode].to_sym
  when :coordination
    observations.uniq.length == 1
  when :prescriptive
    expected = constraint[:canonical_value] || constraint[:canonical_key]
    observations.all? { |value| value == expected }
  else
    false
  end
end
```

### 5. Promotion Reads Both Reliability and Contract Signals

Promotion policy remains reliability-first for ranking execution stability, but correctness gates can now use profile-compliance evidence for profile-enabled roles.

```ruby
def eligible_for_durable?(scorecard:, profile_compliance:)
  reliable = durable_gate_v1_pass?(scorecard)
  correct = profile_compliance.nil? || profile_compliance.fetch(:continuity_pass_rate, 1.0) >= 0.99
  reliable && correct
end
```

This keeps the separation of concerns:

1. scorecards measure reliability,
2. role profiles define semantic correctness.

### 6. Shadow First, Then Enforcement

Continuity guard starts in observational shadow mode for profile-enabled roles:

1. log violations and suggested corrections,
2. calibrate false holds/false violations,
3. enable recoverable enforcement only after shadow evidence is clean.

### 7. Profile Lifecycle Uses ADR 0025 Control Plane

Role-profile lifecycle operations must use ADR 0025 proposal and authority primitives:

1. profile creation/version bump/constraint mode change is represented as `role_profile_update` proposal artifact,
2. profile enactment requires explicit maintainer approval and apply action,
3. unauthorized mutation attempts must produce typed `authority_denied`,
4. no continuity-enforcement path may bypass proposal/audit lanes.

## Current vs Post-ADR Runtime Shape

### Current

```ruby
calc = Agent.for("calculator", model: MODEL)
calc.memory = 5
calc.add(3) # may read/write :value while setter used :memory
```

No explicit role contract binds sibling methods to a canonical state key.

### Post-ADR Adoption

```ruby
calc = Agent.for(
  "calculator",
  model: MODEL,
  role_profile: calculator_profile
)

calc.memory = 5
calc.add(3)
```

In coordination mode, methods must agree on one key but can converge on `:value` or `:accumulator`.

In prescriptive mode, if profile pins `canonical_key: :value`, drift to `:memory` or `:accumulator` yields typed recoverable continuity violation and repair.

## Scope

In scope:

1. explicit `RoleProfile` contract model,
2. continuity guard integrated into existing validation/retry lanes,
3. observability fields for profile compliance and violations.
4. integration with ADR 0025 proposal/authority workflow for profile lifecycle changes.

Out of scope:

1. auto-inference of role profiles by runtime,
2. domain-specific semantic grading beyond authored profile contract,
3. replacing reliability promotion policy from ADR 0023.
4. bypassing ADR 0025 governance controls for profile updates.

## Consequences

### Positive

1. resolves key-drift class of bugs for foundation roles without ad hoc patches,
2. keeps evolutionary freedom by default through coordination-mode constraints,
3. preserves open-ended prompt-policy reasoning while making contracts explicit.

### Tradeoffs

1. profile authoring overhead for roles that need coherence,
2. additional validation surface and diagnostics to maintain,
3. prescriptive constraints can over-constrain evolution if overused.

## Alternatives Considered

1. rely only on reliability scorecards.
   - Rejected: reliability ranking does not define semantic correctness.
2. prescriptive-only profiles (all constraints pin exact values).
   - Rejected: blocks coherent convention evolution and turns profiles into ceilings.
3. infer profiles automatically from observed behavior.
   - Rejected: violates explicit/opt-in policy and risks category-specific hidden lanes.
4. hardcode calculator-specific continuity logic in runtime.
   - Rejected: non-general and violates ubiquitous-language/contract-first approach.

## Rollout Plan

### Phase 1: Contract and UL

1. add scope-first `RoleProfile` schema with `coordination` and `prescriptive` constraint modes,
2. document calculator profile as reference contract.
3. define `role_profile_update` proposal artifact shape for profile publication/version bumps.
4. remove methods-first examples from ADR/docs.

### Phase 2: Observational Guard (Shadow)

1. run continuity checks in shadow mode using role-wide default scope,
2. record violations and correction hints without blocking execution.
3. include ADR 0025 observability evidence in rollout review:
   - `active_role_profile_version`
   - `self_model.awareness_level`
   - namespace-pressure signals (`namespace_key_collision_count`, `namespace_multi_lifetime_key_count`, `namespace_continuity_violation_count`).

### Phase 3: Recoverable Enforcement

1. enable recoverable enforcement for coordination constraints,
2. route through existing guardrail retry budgets and observability.
3. keep profile activation behind approved proposal apply actions only.

### Phase 4: Prescriptive Constraints and Versioning

1. enable prescriptive constraints selectively where determinism is required,
2. enforce explicit active profile version logging and profile version bump workflow.
3. require maintainer-approved proposal for any switch from coordination -> prescriptive mode.
4. keep prescriptive constraints scope-first unless narrowing is explicitly authored.

### Phase 5: Promotion Coupling

1. add profile-compliance evidence to promotion eligibility for profile-enabled roles,
2. keep non-profile tools on reliability-only lifecycle policy.
3. treat profile-compliance evidence as semantic-correctness signal, not authority signal.

## Evidence from ADR 0025 Rollout

Phase validation traces showed why ADR 0024 is still required after ADR 0025:

1. calls can show `awareness_level: "l3"` with `active_role_profile_version: nil`,
2. reliability outcomes can remain `ok` while deterministic semantics drift (calculator `solve` returned `8.5` for `2x + 5 = 17` in one rerun),
3. therefore awareness/governance readiness does not replace continuity correctness.

## Guardrails

1. profiles remain explicit opt-in artifacts; runtime does not infer them.
2. continuity checks must be deterministic and explainable in logs.
3. profile violations must use existing recoverable lanes before terminal failure.
4. non-profile tools retain current tolerant behavior and promotion semantics.
5. coordination-mode constraints must not force specific key names or shapes.
6. prescriptive constraints must be explicit and reviewable.
7. profile enactment and mode/version mutations must be proposal- and authority-gated via ADR 0025 lanes.
8. default scope is role-wide (`all_methods`); explicit method lists are narrowing exceptions only.
9. no compatibility layer for methods-first schema in runtime hot paths.

## Ubiquitous Language Additions

This ADR introduces canonical terms to add to [`docs/ubiquitous-language.md`](../ubiquitous-language.md):

1. `Role Profile`
2. `Canonical State Key`
3. `State Continuity`
4. `State Continuity Guard`
5. `Profile Compliance`
6. `Profile Drift`
7. `Coordination Constraint`
8. `Prescriptive Constraint`
9. `Active Profile Version`
10. `Constraint Scope`
