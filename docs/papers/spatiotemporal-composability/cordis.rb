# frozen_string_literal: true

# Cordis — a Ruby distillation of "A Programming Paradigm for Spatiotemporal
# Composability" (Shi, Zhang & Cui; Peking University / DeepSeek-AI).
#
# The module is named after the paper's meta-framework (§1.3, contribution 5).
# Every construct cites the Definition, Theorem, or Section it implements, so
# code can be traced back to the paper — and the paper forward to running code.
#
# Contexts are immutable values (frozen); every effect is a pure function from
# a context to a successor context paired with the inverse chosen at that state.
# Purity is what makes the paper's theorems executable: see theorem_checks.rb.
module Cordis
  # id_Γ — the unit of composition (§3.1.1, monoid identity axiom).
  IDENTITY = ->(gamma) { gamma }

  # "A violated precondition is signalled as an error and produces no
  # transition" (§3.2.1, remark after Definition 22).
  class PreconditionViolation < StandardError; end

  # ---------------------------------------------------------------------------
  # Definition 8 — effect functions 𝔈_Γ and their witnessed refinement 𝔈*_Γ.
  #
  # An Effect maps a context γ to a pair (δ, g): the successor state and the
  # inverse chosen *at γ*, at the point of application — not fixed a priori
  # as in the track model of §3.1.1. The witness condition g(δ) = γ holds the
  # inverse to reverting the effect exactly where it was applied.
  # ---------------------------------------------------------------------------
  class Effect
    attr_reader :name

    # The body is the effect function itself: γ → [δ, inverse].
    def initialize(name = "effect", &body)
      @name = name
      @body = body
      freeze
    end

    # e(γ) = (δ, g) — Definition 8.
    def call(gamma)
      @body.call(gamma)
    end

    # The forward map pr₁ ∘ e (Definition 17 names it a generator of 𝔐(e)).
    def forward
      effect = self
      ->(gamma) { effect.call(gamma).first }
    end

    # Membership test for 𝔈*_Γ at γ: the inverse yielded at γ reverts to γ
    # (the witness constraint g(δ) = γ of Definition 8).
    def witnessed_at?(gamma)
      delta, inverse = call(gamma)
      inverse.call(delta) == gamma
    end

    # Definition 9 — effect composition f ⋄ g: g runs first, f second, and the
    # inverses accumulate in the opposite order (s ∘ t): undo f, then undo g.
    # Theorem 10: ⋄ is a monoid; Theorem 11: witnessing survives ⋄. Outcomes
    # (eq. 22) are per-application and are not composed.
    def compose(other)
      f = self
      Effect.new("#{f.name} ⋄ #{other.name}") do |gamma|
        delta, s = other.call(gamma)
        epsilon, t = f.call(delta)
        [epsilon, ->(x) { s.call(t.call(x)) }]
      end
    end

    # The monoid unit η_Γ := γ ↦ (γ, id_Γ) (Theorem 10.1).
    def self.unit
      Effect.new("η") { |gamma| [gamma, IDENTITY] }
    end

    # A pair (f, g) ∈ 𝔗_Γ induces the effect γ ↦ (f(γ), g) — one uniform
    # inverse serving every state (Definition 8, discussion; Theorem 11.2).
    def self.from_pair(name, forward, inverse)
      Effect.new(name) { |gamma| [forward.call(gamma), inverse] }
    end
  end

  # ---------------------------------------------------------------------------
  # Definition 2 — the effect context ∂Γ := Γ × (Γ → Γ).
  #
  # A pair (γ, φ): the current state and the *accumulator*, the composite of
  # the inverses of the effects performed so far. The initial effect context
  # is (γ₀, id_Γ). Soundness invariant (§3.1.1, after Theorem 7): φ(γ) = γ₀.
  # ---------------------------------------------------------------------------
  class EffectContext
    # state is γ, the current context; accumulator is φ, which runs every
    # tracked inverse and thereby recovers γ₀.
    attr_reader :state, :accumulator

    def initialize(state, accumulator = IDENTITY)
      @state = state
      @accumulator = accumulator
      freeze
    end

    # Definition 3 — track_Γ(f, g)(γ, φ) = (f(γ), φ ∘ g): transform the state
    # by f and compose the candidate inverse g onto the accumulator.
    # Theorem 4: tracking is transparent to the forward state.
    # Theorem 5: track is a monoid homomorphism from 𝔗_Γ into ∂Γ → ∂Γ.
    def track(forward, inverse)
      phi = @accumulator
      EffectContext.new(forward.call(@state), ->(x) { phi.call(inverse.call(x)) })
    end

    # Definition 12 — effect_Γ(e)(γ, φ) = ((δ, φ ∘ g), track_Γ(g, pr₁ ∘ e)).
    #
    # Applies a Definition-8 effect and returns [successor, lifted_inverse].
    # The lifted inverse is a transformation of ∂Γ in its own right: its
    # forward map is g, and the way to undo *that* is to perform the effect
    # again (pr₁ ∘ e) — undoing an effect is itself a trackable effect, which
    # is what makes selective revert possible (Theorems 13–15).
    def apply(effect)
      delta, g = effect.call(@state)
      phi = @accumulator
      successor = EffectContext.new(delta, ->(x) { phi.call(g.call(x)) })
      lifted_inverse = ->(ec) { ec.track(g, effect.forward) }
      [successor, lifted_inverse]
    end

    # Definition 6 — recover_Γ(γ, φ) = (φ(γ), id_Γ): apply the accumulated
    # inverses and reset. Theorem 7: tracked effects preserve the recovery
    # result, so recover lands on the initial effect context (eq. 11).
    def recover
      EffectContext.new(@accumulator.call(@state), IDENTITY)
    end

    # The soundness invariant φ(γ) = γ₀ of a state in ∂Γ (§3.1.1).
    def sound?(initial_state)
      @accumulator.call(@state) == initial_state
    end
  end

  # ---------------------------------------------------------------------------
  # Definitions 17 & 19 — transformation monoids and independence of effects.
  #
  # Two effects are independent when every transformation of one commutes with
  # every transformation of the other (clause 1) and neither's transformations
  # disturb the inverse the other yields (clause 2). Independence is what lets
  # inverses run out of LIFO order: Corollary 21 recovers γ₀ under *any*
  # permutation of the reverts — the formal licence for withdrawing one
  # component from a running system (§3.1.3).
  #
  # Function equality is undecidable in general, so the check is extensional:
  # Lemma 18 settles commutation on the generators, and we compare functions
  # pointwise over a caller-supplied sample of states. Contexts are partial
  # (Σ is a partial function): a violated precondition "produces no
  # transition", so commutation compares undefined points as agreeing when
  # both sides are undefined, and inverse-stability constrains only the
  # points where an effect was actually applied.
  # ---------------------------------------------------------------------------
  module Independence
    module_function

    # The generators of 𝔐(e), sampled at the given states: the forward map
    # pr₁ ∘ e together with every inverse e yields there (Definition 17). An
    # effect undefined at a sample state yields no inverse there.
    def generators(effect, states)
      sampled = states.map { |gamma| attempt { effect.call(gamma)[1] } }
      [effect.forward, *sampled.reject { |inverse| inverse == :undefined }]
    end

    def independent?(first, second, states:)
      commutes?(first, second, states) &&
        inverse_stable?(first, second, states) &&
        inverse_stable?(second, first, states)
    end

    # Clause 1 of Definition 19, reduced to generators by Lemma 18.1.
    def commutes?(first, second, states)
      generators(first, states).all? do |f|
        generators(second, states).all? do |g|
          states.all? { |gamma| agree?(-> { f.call(g.call(gamma)) }, -> { g.call(f.call(gamma)) }) }
        end
      end
    end

    # Clause 2 of Definition 19: pr₂(e(g(γ))) = pr₂(e(γ)) for every
    # transformation g of the other effect — foreign moves leave the yielded
    # inverse unchanged (compared pointwise over the samples). Where either
    # application is undefined the clause constrains nothing: there is no
    # applied effect whose inverse could have been disturbed, and domain
    # disagreements are already clause 1's business.
    def inverse_stable?(effect, other, states)
      generators(other, states).all? do |g|
        states.all? do |gamma|
          moved = attempt { effect.call(g.call(gamma))[1] }
          home  = attempt { effect.call(gamma)[1] }
          next true if moved == :undefined || home == :undefined

          states.all? { |x| agree?(-> { moved.call(x) }, -> { home.call(x) }) }
        end
      end
    end

    def attempt(&block)
      block.call
    rescue PreconditionViolation, KeyError
      :undefined
    end

    def agree?(left, right)
      attempt(&left) == attempt(&right)
    end
  end

  # Shared observational structure of coeffect contexts: the satisfaction
  # predicate σ ⊨ d := ∀k ∈ d. k ∈ dom(σ) (eq. 24) — decidable since dom(σ)
  # is finite, and checked at every effect boundary (§3.2.2).
  module Satisfaction
    def satisfies?(spec)
      spec.all? { |key| key?(key) }
    end
  end

  # ---------------------------------------------------------------------------
  # Definition 22 — the coeffect context Σ := (k : K) ⇀ V_k.
  #
  # A finite partial function assigning to each dependency key a typed value:
  # the inversion-of-control container, formalized (§3.2.1). Extension and
  # restriction carry preconditions — a dependency cannot be provided twice
  # nor revoked if absent.
  # ---------------------------------------------------------------------------
  class CoeffectContext
    include Satisfaction

    attr_reader :table

    def initialize(table = {})
      @table = table.freeze
      freeze
    end

    # σ(k) — application, defined when k ∈ dom(σ) (Definition 22).
    def fetch(key)
      raise PreconditionViolation, "get(#{key.inspect}): k ∉ dom(σ)" unless key?(key)

      @table[key]
    end

    # k ∈ dom(σ) — membership (Definition 22).
    def key?(key)
      @table.key?(key)
    end

    # dom(σ).
    def domain
      @table.keys
    end

    # σ[k ↦ v] under the provision precondition k ∉ dom(σ) (Definition 23).
    def bind(key, value)
      raise PreconditionViolation, "set(#{key.inspect}): already provided (k ∈ dom(σ))" if key?(key)

      write(key, value)
    end

    # σ \ k — restriction, defined when k ∈ dom(σ) (Definition 22).
    def unbind(key)
      raise PreconditionViolation, "revoke(#{key.inspect}): k ∉ dom(σ)" unless key?(key)

      remaining = @table.dup
      remaining.delete(key)
      self.class.new(remaining)
    end

    # Raw table update σ[k ↦ v], agreeing with σ elsewhere (Definition 22) —
    # no precondition; operation lifts rebind through it (eq. 23).
    def write(key, value)
      self.class.new(@table.merge(key => value))
    end

    def ==(other)
      other.is_a?(self.class) && table == other.table
    end
    alias eql? ==

    def hash
      [self.class, table].hash
    end
  end

  # ---------------------------------------------------------------------------
  # Definition 23 — the get and set operations on Σ, and Definition 26's
  # classification of context transitions.
  #
  # set(k, v)(σ) = (σ[k ↦ v], λσ′. σ′ \ k) has type 𝔈*_Σ — precisely a
  # witnessed effect function on the coeffect context. "This is the synergy
  # between reactive coeffects and revertible effects: coeffect operations
  # are effects, and effects are revertible" (§3.2.1).
  # ---------------------------------------------------------------------------
  module Coeffects
    module_function

    # get(k)(σ) = σ(k), requiring k ∈ dom(σ) (Definition 23).
    def get(key)
      ->(sigma) { sigma.fetch(key) }
    end

    # set(k, v) as a witnessed effect on Σ (Definition 23).
    def set(key, value)
      Effect.new("set(#{key.inspect})") do |sigma|
        [sigma.bind(key, value), ->(next_sigma) { next_sigma.unbind(key) }]
      end
    end

    # notify_d(σ, σ′) — Definition 26: classify a transition against a
    # coeffect specification d (Definition 25, a set of keys) as activating,
    # deactivating, or neutral.
    def notify(spec, before, after)
      was = before.satisfies?(spec)
      now = after.satisfies?(spec)
      return :activating if !was && now
      return :deactivating if was && !now

      :neutral
    end
  end

  # ---------------------------------------------------------------------------
  # Definition 24 — a coeffect at a key k is a triple (V_k, ≈_k, A_k): the
  # value type, an equivalence up to which values at k are compared, and the
  # operations the value provides to a component holding it.
  #
  # An operation a ∈ A_k acts on the value alone (eq. 22) and is lifted to Σ
  # by eq. 23: it reads the binding at k, transforms it, and its inverse
  # applies the value-level inverse g to *whatever value σ′ then holds at k* —
  # which is what confines the operation to its key and keeps it independent
  # of every other key (§3.2.1, remark after eq. 23).
  # ---------------------------------------------------------------------------
  class Coeffect
    attr_reader :key, :value_type, :equivalence

    def initialize(key, value_type: Object, equivalence: ->(a, b) { a == b })
      @key = key
      @value_type = value_type
      @equivalence = equivalence
      @operations = {}
    end

    # Declare an operation a : X_a → V_k → V_k × (V_k ⇀ V_k) × B_a (eq. 22).
    # The block maps (argument, value) to [new_value, value_inverse, outcome].
    def operation(name, &body)
      @operations[name] = body
      self
    end

    # The lift a^Σ (eq. 23): defined when k ∈ dom(σ); its first two
    # constituents form an effect function on Σ, and the third is the outcome
    # b : B_a, paired with each application (eq. 22) — every call yields its
    # own [σ′, inverse, outcome] triple.
    def lift(name, argument)
      body = @operations.fetch(name)
      key = @key
      Effect.new("#{key.inspect}.#{name}") do |sigma|
        value, inverse, outcome = body.call(argument, sigma.fetch(key))
        [sigma.write(key, value), ->(next_sigma) { next_sigma.write(key, inverse.call(next_sigma.fetch(key))) }, outcome]
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Definition 28 — the coeffect context with isolation Σ^iso := (ρ, σ).
  #
  # Two layers: ρ assigns realm identifiers to keys (a key outside dom(ρ)
  # resolves to its own realm), σ maps realm identifiers to values. The same
  # logical key can bind different values in different contexts — runtime
  # ad-hoc polymorphism for sandboxes, tenants, and tests (§3.2.3).
  # ---------------------------------------------------------------------------
  class IsolatedContext
    include Satisfaction

    attr_reader :realms, :table # ρ, σ

    def initialize(realms = {}, table = {})
      @realms = realms.freeze
      @table = table.freeze
      freeze
    end

    # ρ(k), with ρ(k) = k for keys outside dom(ρ) (Definition 28).
    def resolve(key)
      @realms.fetch(key, key)
    end

    # get(k)(ρ, σ) = σ(ρ(k)) (Definition 29), precondition ρ(k) ∈ dom(σ).
    def fetch(key)
      raise PreconditionViolation, "get(#{key.inspect}): ρ(k) ∉ dom(σ)" unless key?(key)

      @table[resolve(key)]
    end

    def key?(key)
      @table.key?(resolve(key))
    end

    # set(k, v) transported along ρ (Definition 29): writes σ[ρ(k) ↦ v] under
    # the precondition ρ(k) ∉ dom(σ). Per eq. 28 the inverse restricts at
    # ρ′(k) — the realm is re-resolved in the context the inverse is applied
    # to, which is exactly what unbind below does on its receiver.
    def bind(key, value)
      realm = resolve(key)
      raise PreconditionViolation, "set(#{key.inspect}): already provided in realm #{realm.inspect}" if @table.key?(realm)

      self.class.new(@realms, @table.merge(realm => value))
    end

    def unbind(key)
      realm = resolve(key)
      raise PreconditionViolation, "revoke(#{key.inspect}): ρ(k) ∉ dom(σ)" unless @table.key?(realm)

      remaining = @table.dup
      remaining.delete(realm)
      self.class.new(@realms, remaining)
    end

    # isolate(k, r)(ρ, σ) = (ρ[k ↦ r], σ) — Definition 29. A *derived*
    # realization (Definition 27): it leaves the shared table as it stands and
    # returns a fresh context deriving from it, with the identity as inverse —
    # there is no inverse to track, and recovery discards the derived context.
    # A key already isolated is reassigned rather than refused.
    def isolate(key, realm)
      self.class.new(@realms.merge(key => realm), @table)
    end

    def ==(other)
      other.is_a?(self.class) && realms == other.realms && table == other.table
    end
    alias eql? ==

    def hash
      [self.class, realms, table].hash
    end
  end

  # ---------------------------------------------------------------------------
  # Definitions 30 & 31 — the coeffect context with interception:
  # Σ^inter := ((k : K) → M_k) × ((k : K) ⇀ (M_k → V_k)), a pair (ι, σ) of
  # context-carried metadata and provider functions, each key equipped with a
  # metadata monoid (M_k, ⊕_k, ε_k).
  #
  # get(k, μ)(ι, σ) = σ(k)(μ ⊕_k ι(k)): the component-declared metadata μ is
  # merged with the context-carried ι(k) and the provider function is applied
  # to the result. The merge is right-biased, so ι(k) takes priority — an
  # enclosing context can constrain how a component uses a coeffect without
  # modifying that component (§6.3). intercept(k, ν) derives a fresh context
  # merging ν onto the inherited metadata, the provider table untouched —
  # like isolate, a derived realization (Definition 27) with nothing to track.
  # ---------------------------------------------------------------------------
  class InterceptedContext
    include Satisfaction

    EMPTY = {}.freeze
    MERGE = ->(left, right) { left.merge(right) } # ⊕_k for hash metadata; right-biased

    attr_reader :metadata, :providers # ι, σ

    def initialize(metadata = {}, providers = {}, merge: MERGE, empty: EMPTY)
      @metadata = metadata.freeze
      @providers = providers.freeze
      @merge = merge
      @empty = empty
      freeze
    end

    # get(k, μ)(ι, σ) = σ(k)(μ ⊕_k ι(k)) — Definition 31, eq. 30.
    def fetch(key, declared = @empty)
      raise PreconditionViolation, "get(#{key.inspect}): k ∉ dom(σ)" unless key?(key)

      @providers[key].call(@merge.call(declared, @metadata.fetch(key, @empty)))
    end

    def key?(key)
      @providers.key?(key)
    end

    # set(k, ψ) — an effect on the provider table under the Definition 23
    # precondition, its inverse the restriction λσ′. σ′ \ k (eq. 30).
    def bind(key, provider)
      raise PreconditionViolation, "set(#{key.inspect}): already provided" if key?(key)

      self.class.new(@metadata, @providers.merge(key => provider), merge: @merge, empty: @empty)
    end

    def unbind(key)
      raise PreconditionViolation, "revoke(#{key.inspect}): k ∉ dom(σ)" unless key?(key)

      remaining = @providers.dup
      remaining.delete(key)
      self.class.new(@metadata, remaining, merge: @merge, empty: @empty)
    end

    # intercept(k, ν)(ι, σ) = (ι[k ↦ ι(k) ⊕_k ν], σ) — derived, no inverse.
    def intercept(key, extra)
      merged = @merge.call(@metadata.fetch(key, @empty), extra)
      self.class.new(@metadata.merge(key => merged), @providers, merge: @merge, empty: @empty)
    end

    def ==(other)
      other.is_a?(self.class) && metadata == other.metadata && providers == other.providers
    end
    alias eql? ==

    def hash
      [self.class, metadata, providers].hash
    end
  end

  # ---------------------------------------------------------------------------
  # A component — the unit of dynamic composition (§1.3, contribution 4).
  #
  # It declares the coeffects it requires as a specification (Definition 25)
  # and expresses what it does to the context as witnessed effects performed
  # on activation. Its lifecycle is not called; it *reacts* (Definition 26).
  # ---------------------------------------------------------------------------
  class Component
    attr_reader :name, :requires

    def initialize(name, requires: [], &activation)
      @name = name
      @requires = requires.freeze
      @activation = activation
      freeze
    end

    def activate(scope)
      @activation&.call(scope)
    end
  end

  # What an activating component sees: reads through get (Definition 23) and
  # provisions through witnessed set effects, each inverse joining the
  # component's own accumulator (§3.1.3: "one sequence may interleave the
  # effects of several components, each keeping the inverses of its own").
  class ActivationScope
    def initialize(system, entry)
      @system = system
      @entry = entry
    end

    def get(key)
      Coeffects.get(key).call(@system.context)
    end

    def provide(key, value)
      @system.perform(Coeffects.set(key, value), @entry, undo_tag: key)
    end

    # Perform any witnessed effect (e.g. a Coeffect operation lift, eq. 23).
    def apply(effect)
      @system.perform(effect, @entry)
    end
  end

  # ---------------------------------------------------------------------------
  # The reactive runtime — the reactive invariant of §3.2.2 made operational.
  #
  # Every mutation of the shared context is an effect function; every
  # transition it produces is classified against every mounted component's
  # specification (Definition 26). An activating transition runs the
  # component's effects with full tracking; a deactivating transition runs
  # its accumulator, in LIFO order (Theorem 16). A withdrawal is ordered
  # *after* the deactivations it causes (§3.2.2, closing paragraph — the
  # excerpt defers the formal machinery to §4.3.1); reverting one component's
  # accumulator out of global order is licensed by independence: components
  # touch disjoint keys, so Corollary 21 applies.
  # ---------------------------------------------------------------------------
  class System
    Entry = Struct.new(:component, :undo, :active, :host)

    attr_reader :context, :initial, :trace

    def initialize(context = CoeffectContext.new)
      @context = context
      @initial = context
      @entries = {}
      @trace = []
    end

    def active
      @entries.values.select { |entry| entry.active && !entry.host }.map { |entry| entry.component.name }
    end

    # Component arrival. Mounting does not transform σ; the component
    # activates immediately iff σ already satisfies its specification —
    # "a component activates only at a state satisfying its specification,
    # so it never reads a binding that is absent" (§3.2.2). Mounting an
    # already-mounted name would orphan its accumulator, so it is refused —
    # the same discipline as the no-double-provision precondition.
    def mount(component)
      raise PreconditionViolation, "mount(#{component.name}): already mounted" if @entries.key?(component.name)

      entry = Entry.new(component, [], false)
      @entries[component.name] = entry
      log "mount    #{component.name}  (requires #{component.requires.inspect})"
      activate(entry) if @context.satisfies?(component.requires)
      self
    end

    # Component departure: unloading is applying the component's accumulator
    # (§3.1.3, closing criterion), then forgetting it.
    def unmount(name)
      entry = @entries.fetch(name)
      log "unmount  #{name}"
      deactivate(entry) if entry.active
      @entries.delete(name)
      self
    end

    # A provision made by the host environment rather than a component.
    def provide(key, value)
      perform(Coeffects.set(key, value), host_entry, undo_tag: key)
    end

    # Host-side withdrawal of a provision — realized as the *selective revert*
    # of the recorded set effect: its witnessed inverse is applied at a state
    # later effects have moved, exactly the situation Corollary 21 covers.
    def revoke(key)
      entry = host_entry
      index = entry.undo.rindex { |(undo_key, _)| undo_key == key }
      raise PreconditionViolation, "revoke(#{key.inspect}): the host provided no such key" unless index

      _, inverse = entry.undo.delete_at(index)
      transition("revert set(#{key.inspect})", inverse)
      self
    end

    # Witnessed application (Definition 8): σ ↦ (δ, g). The successor becomes
    # the shared context; the inverse joins the owner's accumulator (§3.1.3),
    # tagged so a selective revert can find it again.
    def perform(effect, entry, undo_tag: nil)
      inverse = transition(effect.name, effect)
      entry.undo << [undo_tag, inverse] if inverse
      self
    end

    private

    def host_entry
      @entries[:host] ||= Entry.new(Component.new("host"), [], true, true)
    end

    # One reactive step. `step` is an Effect or a bare inverse Γ → Γ.
    def transition(label, step)
      probe = probe_successor(step)
      # §3.2.2: order the withdrawal after the deactivations it causes.
      (@context.domain - probe.domain).each { |key| deactivate_dependents(key) }
      before = @context
      after, inverse = run_step(step, before)
      @context = after
      log "effect   #{label}"
      begin
        classify(before, after)
      rescue StandardError
        # A failed cascade must not strand the effect that triggered it.
        # Withdrawing it is itself a classified transition, so successful
        # activations unwind in dependency order and "a violated precondition
        # produces no transition" (§3.2.1) holds one level up as well.
        transition("rollback #{label}", inverse) if inverse
        raise
      end
      inverse
    end

    def probe_successor(step)
      step.is_a?(Effect) ? step.call(@context).first : step.call(@context)
    end

    def run_step(step, sigma)
      step.is_a?(Effect) ? step.call(sigma) : [step.call(sigma), nil]
    end

    # Definition 26 applied to every mounted specification. Deactivations were
    # ordered before the transition; what remains to react to is activation.
    def classify(before, after)
      @entries.each_value do |entry|
        next if entry.host

        verdict = Coeffects.notify(entry.component.requires, before, after)
        activate(entry) if verdict == :activating && !entry.active
        deactivate(entry) if verdict == :deactivating && entry.active # defensive; pre-ordered above
      end
    end

    # The reactive invariant, activating half: "an activating transition
    # triggers execution of the component's effects (with full effect
    # tracking)" (§3.2.2, after Definition 26). A component whose activation
    # fails is deactivated on the spot — its partial effects are recovered
    # from its own accumulator — and the failure propagates to the transition
    # that triggered it.
    def activate(entry)
      entry.active = true
      log "activate #{entry.component.name}"
      entry.component.activate(ActivationScope.new(self, entry))
    rescue StandardError
      deactivate(entry)
      raise
    end

    # Deactivating half: "a deactivating transition triggers recovery by
    # applying the accumulator" — the component's own inverses, in LIFO order
    # (Theorem 16), each application itself a classified transition.
    def deactivate(entry)
      entry.active = false
      log "deactivate #{entry.component.name}"
      while (tag_and_inverse = entry.undo.pop)
        tag, inverse = tag_and_inverse
        transition(tag ? "revert set(#{tag.inspect})" : "revert #{entry.component.name} effect", inverse)
      end
    end

    def deactivate_dependents(key)
      @entries.each_value do |entry|
        deactivate(entry) if entry.active && !entry.host && entry.component.requires.include?(key)
      end
    end

    def log(line)
      @trace << line
    end
  end
end
