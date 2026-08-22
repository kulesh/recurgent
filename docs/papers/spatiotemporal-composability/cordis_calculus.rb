# frozen_string_literal: true

# The calculus of dynamic composition (§4), executable.
#
# Section 4 decomposes a running system into fibers — instantiations of
# components carrying lifecycle state — and gives ten rules that move them.
# This file implements that operational semantics directly: the state γ is a
# registry of fibers (Definition 45), the coeffect context is derived from
# the Active fibers (eq. 40), the target view drives every transition
# (Definition 46), and the rules of §4.2–§4.3 are methods that fire when
# their premises hold. calculus_checks.rb runs the metatheory of §4.4
# against random schedules.
#
# Modeling choices, stated once:
# - Effects are iterators (Definition 51): a component's body is a sequence
#   of steps, one consumed per L-Iter, each yielding its inverse; a step is
#   a provision into the fiber's own table (confinement, Definition 48), a
#   registration of a child component (Definition 47), or a raise (§4.3.4).
# - Steps are atomic, so the aborting and landing alternatives of L-Divert
#   coincide at every iteration boundary (§4.3.3's inertia is the statement
#   that only the landing alternative exists once an iteration is in
#   flight; with atomic iterations the boundary is always at hand).
# - Names are atoms the rules only compare (§4.1); we draw registration
#   names deterministically per (parent, component, occurrence) so that two
#   schedules of the same orchestration steps are comparable without the
#   renaming of Lemma 56.

require_relative "cordis"

module Cordis
  module Calculus
    # Definition 43 — a component over Γ is a triple (d, p, e): the coeffect
    # specification, the provision, and the effect function, here an iterator
    # given as a list of steps.
    class Component
      attr_reader :id, :inject, :provide, :steps

      def initialize(id, inject: [], provide: [], steps: [])
        @id = id
        @inject = inject.freeze
        @provide = provide.freeze
        @steps = steps.freeze
        freeze
      end

      # Small builder: set/register/fail! append steps (Definition 51's
      # iterations, in order).
      def self.build(id, inject: [], provide: [])
        builder = StepBuilder.new
        yield builder if block_given?
        new(id, inject: inject, provide: provide, steps: builder.steps)
      end

      class StepBuilder
        attr_reader :steps

        def initialize
          @steps = []
        end

        def set(key, value = nil, &block)
          @steps << [:set, key, block || value]
        end

        def register(component, config = nil)
          @steps << [:register, component, config]
        end

        def fail!(error)
          @steps << [:fail, error]
        end
      end
    end

    # Definition 44 — a fiber ⟨d, p, e, π, σ, τ, θ⟩: the component fields, the
    # parent, the fiber's own coeffect table, the retirement flag, and the
    # lifecycle state θ (Definition 49):
    #   Inactive(ζ) | Reloading(i, g, ω) | Active(g, ω) | Unloading(g, ω, ζ)
    # where i is the remaining iterator, g the accumulator built so far
    # (a stack of inverses, applied LIFO), ω the committed view d → 𝔑, and ζ
    # the outcome — ⊥ or an error (§4.3.4).
    class Fiber
      attr_reader :component, :parent
      attr_accessor :table, :retired, :state, :remaining, :accumulator, :committed, :outcome

      def initialize(component, parent)
        @component = component
        @parent = parent
        @table = {}        # σ_n — empty until its effects run (Definition 44)
        @retired = false   # τ_n
        @state = :inactive # θ_n
        @remaining = nil   # i — remaining iterations while Reloading
        @accumulator = []  # g — inverses, most recent last
        @committed = nil   # ω — the committed view
        @outcome = nil     # ζ — ⊥ (nil) or an error
      end

      def inject = component.inject
      def provide = component.provide

      # installed_n(γ) := θ_n ≠ Inactive(−)  (eq. 44)
      def installed? = state != :inactive

      def failed? = state == :inactive && !outcome.nil?

      # Lemma 57 — a vestigial entry: retired, Inactive(⊥), empty table.
      def vestigial? = retired && state == :inactive && outcome.nil? && table.empty?
    end

    # The state γ: the registry F_γ (Definition 45) plus the rule engine.
    class Machine
      attr_reader :fibers, :trace

      def initialize(seed: 0)
        @fibers = {}
        @trace = []
        @rng = Random.new(seed)
        @registration_counters = Hash.new(0)
      end

      # --- Definition 45 / eq. 40: the derived coeffect context -------------
      # σ_γ := ⋃ { σ_m | θ_m = Active(−, −) } — Active fibers alone, which is
      # what makes a withdrawal visible one step before it happens (L-Leave).
      def sigma
        @fibers.values.select { |f| f.state == :active }.each_with_object({}) do |fiber, table|
          table.merge!(fiber.table)
        end
      end

      # provider_k(γ) — unique because provisions are disjoint (Definition 43).
      def provider(key)
        @fibers.find { |_, f| f.state == :active && f.table.key?(key) }&.first
      end

      # --- Definition 46 / eq. 41: the target view --------------------------
      # ⊥ when the fiber ought not to be running; otherwise each declared key
      # mapped to its provider.
      def target(name)
        fiber = @fibers.fetch(name)
        return nil if fiber.retired

        view = {}
        fiber.inject.each do |key|
          provider_name = provider(key)
          return nil unless provider_name

          view[key] = provider_name
        end
        view
      end

      # --- eq. 45: quiescence on the four-state space ------------------------
      def quiet?
        @fibers.all? do |name, fiber|
          case fiber.state
          when :inactive then !fiber.outcome.nil? || target(name).nil?
          when :active then target(name) == fiber.committed
          else false
          end
        end
      end

      # --- Definition 50 / eq. 46: relied upon --------------------------------
      # Some other installed fiber resolves a key to n through its committed view.
      def relied?(name)
        @fibers.any? do |m, fiber|
          m != name && fiber.installed? && fiber.committed&.value?(name)
        end
      end

      # --- Definition 58: well-formedness (checked by Theorem 59's client) ---
      def well_formed?
        @fibers.all? do |name, fiber|
          parent_ok = fiber.parent == :root || @fibers.key?(fiber.parent)
          disjoint = @fibers.none? { |m, other| m != name && other.provide.intersect?(fiber.provide) }
          parent_ok && disjoint && committed_view_well_formed?(fiber)
        end
      end

      # Clauses (3) and (4) of Definition 58: an installed fiber's committed
      # view is total on its specification, valued in the registry, and names
      # installed providers only.
      def committed_view_well_formed?(fiber)
        return true unless fiber.installed?

        fiber.inject.all? { |k| @fibers.key?(fiber.committed&.[](k)) } &&
          fiber.committed.values.all? { |m| @fibers[m].installed? }
      end

      # ====================== orchestration rules (γ ⇒ δ) =====================

      # O-Insert: freshness, parent present, provisions disjoint from every
      # fiber's (the single-source discipline).
      def o_insert(name, component, parent: :root)
        premise !@fibers.key?(name), "O-Insert: #{name} not fresh"
        premise parent == :root || @fibers.key?(parent), "O-Insert: parent absent"
        clash = @fibers.values.any? { |f| f.provide.intersect?(component.provide) }
        premise !clash, "O-Insert: provisions not disjoint"
        @fibers[name] = Fiber.new(component, parent)
        log :o_insert, name
        self
      end

      # O-Retire: unconditional on the fiber's state — a request; the
      # lifecycle rules carry it out.
      def o_retire(name)
        premise @fibers.key?(name), "O-Retire: #{name} absent"
        @fibers[name].retired = true
        log :o_retire, name
        self
      end

      # O-Remove: retired, Inactive, and childless — removing earlier would
      # discard the accumulator and leak.
      def o_remove(name)
        fiber = @fibers.fetch(name)
        premise fiber.retired, "O-Remove: not retired"
        premise fiber.state == :inactive, "O-Remove: not Inactive"
        premise @fibers.none? { |_, f| f.parent == name }, "O-Remove: has children"
        @fibers.delete(name)
        log :o_remove, name
        self
      end

      # ======================= lifecycle rules (γ ⟶ δ) ========================
      # Each returns true if its premises held and it fired.
      # rubocop:disable Naming/PredicateMethod -- the names mirror the paper's rules

      # L-Begin: Inactive(⊥) with a target view — commit the view, start the
      # iterator with an empty accumulator.
      def l_begin(name)
        fiber = @fibers.fetch(name)
        view = target(name)
        return false unless fiber.state == :inactive && fiber.outcome.nil? && view

        fiber.state = :reloading
        fiber.remaining = fiber.component.steps.dup
        fiber.accumulator = []
        fiber.committed = view
        log :l_begin, name
        true
      end

      # L-Iter / L-Finish: run one iteration while the committed view is still
      # the target view; the yielded inverse composes onto the accumulator
      # (LIFO); the final iteration lands in Active.
      def l_step(name)
        fiber = @fibers.fetch(name)
        return false unless fiber.state == :reloading && target(name) == fiber.committed
        return false if next_step_raises?(fiber)

        if fiber.remaining.empty?
          fiber.state = :active
          fiber.remaining = nil
          log :l_finish, name
        else
          run_iteration(fiber, fiber.remaining.shift)
          log :l_iter, name
        end
        true
      end

      # L-Divert: the target view turned during the transition — route through
      # Unloading with the accumulator built so far (the aborting alternative;
      # see the modeling note at the top).
      def l_divert(name)
        fiber = @fibers.fetch(name)
        return false unless fiber.state == :reloading && target(name) != fiber.committed

        fiber.state = :unloading
        fiber.remaining = nil
        fiber.outcome = nil
        log :l_divert, name
        true
      end

      # L-Raise: an iteration raises in place of yielding (§4.3.4, eq. 49);
      # not conditioned on the target view at all.
      def l_raise(name)
        fiber = @fibers.fetch(name)
        return false unless fiber.state == :reloading && next_step_raises?(fiber)

        error = fiber.remaining.first[1]
        fiber.state = :unloading
        fiber.remaining = nil
        fiber.outcome = error
        log :l_raise, name
        true
      end

      # L-Leave: record the decision to deactivate without acting on it — the
      # fiber stops providing (σ_γ unions Active alone) while its committed
      # view, and everyone else's, stays intact.
      def l_leave(name)
        fiber = @fibers.fetch(name)
        return false unless fiber.state == :active && target(name) != fiber.committed

        fiber.state = :unloading
        log :l_leave, name
        true
      end

      # L-Unload: guarded by ¬relied_n(γ) — the withdrawal of a key takes
      # effect only after every consumer that resolved it here has gone
      # (Definition 50). The one rule that applies an accumulator.
      def l_unload(name)
        fiber = @fibers.fetch(name)
        return false unless fiber.state == :unloading && !relied?(name)

        fiber.accumulator.reverse_each(&:call) # LIFO recovery (Theorem 16)
        fiber.accumulator = []
        fiber.committed = nil
        fiber.state = :inactive
        log :l_unload, name
        true
      end

      # rubocop:enable Naming/PredicateMethod

      # ============================ the driver =================================

      LIFECYCLE_RULES = %i[l_begin l_step l_divert l_raise l_leave l_unload].freeze

      # One nondeterministic lifecycle step — an action that reports whether
      # any rule fired, so `step` keeps the paper's word for it. Collect every
      # (rule, fiber) whose premises hold and fire one at random: "no rule
      # mentions a scheduler; a theorem proved over all sequences holds for
      # every scheduling policy" (§4.2) — the seed picks the policy.
      # rubocop:disable Naming/PredicateMethod
      def step
        applicable = @fibers.keys.flat_map do |name|
          LIFECYCLE_RULES.select { |rule| applicable?(rule, name) }.map { |rule| [rule, name] }
        end
        return false if applicable.empty?

        rule, name = applicable[@rng.rand(applicable.length)]
        send(rule, name)
        true
      end
      # rubocop:enable Naming/PredicateMethod

      # Run lifecycle steps to quiescence. Theorem 66 bounds every maximal
      # sequence, so the cap is a defect detector, not a terminator.
      def run(max_steps: 10_000)
        steps = 0
        while step
          steps += 1
          raise "progress violated: #{steps} steps without quiescence" if steps > max_steps
        end
        raise "stuck: no rule applies but the state is not quiescent" unless quiet?

        self
      end

      # Snapshot for ≈-comparison (eq. 53 read at quiescence): every
      # non-vestigial fiber's identity and state; Lemma 57 is why vestigial
      # entries may be dropped.
      def snapshot
        @fibers.reject { |_, f| f.vestigial? }.to_h do |name, fiber|
          [name, [fiber.component.id, fiber.parent, fiber.retired, fiber.table,
                  fiber.state, fiber.committed, fiber.outcome]]
        end
      end

      private

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- one case arm per rule
      def applicable?(rule, name)
        fiber = @fibers.fetch(name)
        view = target(name)
        case rule
        when :l_begin then fiber.state == :inactive && fiber.outcome.nil? && !view.nil?
        when :l_step then fiber.state == :reloading && view == fiber.committed && !next_step_raises?(fiber)
        when :l_divert then fiber.state == :reloading && view != fiber.committed
        when :l_raise then fiber.state == :reloading && next_step_raises?(fiber)
        when :l_leave then fiber.state == :active && view != fiber.committed
        when :l_unload then fiber.state == :unloading && !relied?(name)
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def next_step_raises?(fiber)
        fiber.remaining&.first&.first == :fail
      end

      # One iteration of the effect iterator: perform the step, push its
      # inverse. Reads go through the committed view ω — the resolution the
      # transition committed to (Definition 46), not the live store.
      def run_iteration(fiber, step)
        kind, a, b = step
        case kind
        when :set
          value = b.respond_to?(:call) ? b.call(reads_of(fiber)) : b
          fiber.table[a] = value
          fiber.accumulator << -> { fiber.table.delete(a) }
        when :register
          child = register(fiber, a, b)
          fiber.accumulator << -> { o_retire(child) } # the inverse retires, never removes (Definition 47)
        end
      end

      def reads_of(fiber)
        fiber.committed.to_h { |key, provider_name| [key, @fibers.fetch(provider_name).table[key]] }
      end

      # Definition 47 — registration: an O-Insert taken by an iteration, with
      # π = n; the name is drawn fresh and deterministically (see header note).
      def register(fiber, component, _config)
        parent_name = @fibers.key(fiber)
        counter_key = [parent_name, component.id]
        occurrence = @registration_counters[counter_key]
        @registration_counters[counter_key] += 1
        child_name = "#{parent_name}/#{component.id}##{occurrence}"
        o_insert(child_name, component, parent: parent_name)
        child_name
      end

      def premise(condition, message)
        raise PreconditionViolation, message unless condition
      end

      def log(rule, name)
        @trace << [rule, name]
      end
    end
  end
end
