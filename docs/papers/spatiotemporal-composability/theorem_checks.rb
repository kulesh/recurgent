# frozen_string_literal: true

# Executable checks for the theorems of "A Programming Paradigm for
# Spatiotemporal Composability", run against the Cordis distillation.
#
# Function equality is checked extensionally: two transformations count as
# equal when they agree on every probe state below. The theorems are proved
# in the paper for all states; these checks witness them on concrete ones.
#
# Run: ruby theorem_checks.rb

require_relative "cordis"

FAILURES = [] # rubocop:disable Style/MutableConstant -- appended to as checks run

def check(label)
  yield
  puts "  ✓ #{label}"
rescue StandardError => e
  FAILURES << label
  puts "  ✗ #{label}: #{e.class}: #{e.message}"
end

def assert(condition, message = "expected condition to hold")
  raise message unless condition
end

def assert_equal(expected, actual)
  raise "expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
end

def assert_raises(klass)
  yield
  raise "expected #{klass} to be raised"
rescue klass
  true
end

# --- Sample contexts and effects --------------------------------------------
#
# Γ is a frozen Hash. `assign` is the canonical witnessed effect: its inverse
# is chosen per state (Definition 8) — it restores whatever the key held at
# the moment of application, or deletes the key if it was absent.

def hash_write(gamma, key, value)
  gamma.merge(key => value).freeze
end

def hash_delete(gamma, key)
  gamma.reject { |k, _| k == key }.freeze
end

def assign(key, value)
  Cordis::Effect.new("assign(#{key}, #{value})") do |gamma|
    inverse =
      if gamma.key?(key)
        previous = gamma[key]
        ->(x) { hash_write(x, key, previous) }
      else
        ->(x) { hash_delete(x, key) }
      end
    [hash_write(gamma, key, value), inverse]
  end
end

def increment(key)
  Cordis::Effect.new("increment(#{key})") do |gamma|
    [hash_write(gamma, key, gamma.fetch(key) + 1), ->(x) { hash_write(x, key, x.fetch(key) - 1) }]
  end
end

GAMMA0 = { a: 1, b: 2, c: 10 }.freeze
PROBES = [GAMMA0, { a: 5, b: 2, c: 0 }.freeze, { a: 1, b: 7, c: 3, d: 4 }.freeze].freeze

def same_fn?(left, right, probes = PROBES)
  probes.all? { |gamma| left.call(gamma) == right.call(gamma) }
end

def same_effect?(left, right, probes = PROBES)
  probes.all? do |gamma|
    ld, li = left.call(gamma)
    rd, ri = right.call(gamma)
    ld == rd && same_fn?(li, ri, probes)
  end
end

def same_effect_context?(left, right, probes = PROBES)
  left.state == right.state && probes.all? { |gamma| left.accumulator.call(gamma) == right.accumulator.call(gamma) }
end

puts "§3.1.1 — Effect context, track, recover"

# Definition 1 — the twisted composition (f₁, g₁) ∘ (f₂, g₂) = (f₁ ∘ f₂, g₂ ∘ g₁).
def twisted_compose(pair1, pair2)
  f1, g1 = pair1
  f2, g2 = pair2
  [->(x) { f1.call(f2.call(x)) }, ->(x) { g2.call(g1.call(x)) }]
end

PAIR_DOUBLE_A = [->(g) { hash_write(g, :a, g.fetch(:a) * 2) }, ->(g) { hash_write(g, :a, g.fetch(:a) / 2) }].freeze
PAIR_INC_B    = [->(g) { hash_write(g, :b, g.fetch(:b) + 1) }, ->(g) { hash_write(g, :b, g.fetch(:b) - 1) }].freeze

check "Theorem 4: pr₁ ∘ track(f, g) = f ∘ pr₁ — tracking is transparent to the forward state" do
  f, g = PAIR_DOUBLE_A
  PROBES.each do |gamma|
    ec = Cordis::EffectContext.new(gamma, Cordis::IDENTITY)
    assert_equal f.call(gamma), ec.track(f, g).state
  end
end

check "Theorem 5: track is a monoid homomorphism — track(p₁ ∘ p₂) = track(p₁) ∘ track(p₂)" do
  f12, g12 = twisted_compose(PAIR_DOUBLE_A, PAIR_INC_B)
  PROBES.each do |gamma|
    ec = Cordis::EffectContext.new(gamma, Cordis::IDENTITY)
    via_twisted = ec.track(f12, g12)
    via_sequence = ec.track(*PAIR_INC_B).track(*PAIR_DOUBLE_A) # track(p₁) ∘ track(p₂) acts right first
    assert same_effect_context?(via_twisted, via_sequence)
  end
end

check "Theorem 7 / eq. 11: recover ∘ track = recover; a tracked sequence recovers (γ₀, id)" do
  ec = Cordis::EffectContext.new(GAMMA0)
  tracked = ec.track(*PAIR_DOUBLE_A)
  assert same_effect_context?(ec.recover, tracked.recover)

  sequence = ec.track(*PAIR_DOUBLE_A).track(*PAIR_INC_B).track(*PAIR_DOUBLE_A)
  recovered = sequence.recover
  assert_equal GAMMA0, recovered.state
  assert same_fn?(recovered.accumulator, Cordis::IDENTITY)
end

check "Soundness invariant: φ(γ) = γ₀ at every state a tracked sequence reaches" do
  ec = Cordis::EffectContext.new(GAMMA0)
  [PAIR_DOUBLE_A, PAIR_INC_B, PAIR_DOUBLE_A].each do |pair|
    ec = ec.track(*pair)
    assert ec.sound?(GAMMA0)
  end
end

puts "§3.1.2 — Effect functions, ⋄, the lift to ∂Γ"

E_ASSIGN_A = assign(:a, 100)
E_ASSIGN_D = assign(:d, 4)
E_INC_C = increment(:c)

check "Definition 8: effects choose their inverse per state, and are witnessed there" do
  PROBES.each { |gamma| assert E_ASSIGN_A.witnessed_at?(gamma) }
  delta, inverse = E_ASSIGN_A.call(GAMMA0)
  assert_equal 100, delta[:a]
  assert_equal GAMMA0, inverse.call(delta) # g(δ) = γ — the witness constraint
end

check "Theorem 10: (𝔈_Γ, ⋄) is a monoid — associativity and unit η" do
  left = E_ASSIGN_A.compose(E_INC_C).compose(E_ASSIGN_D)
  right = E_ASSIGN_A.compose(E_INC_C.compose(E_ASSIGN_D))
  assert same_effect?(left, right)
  eta = Cordis::Effect.unit
  assert same_effect?(E_INC_C, eta.compose(E_INC_C))
  assert same_effect?(E_INC_C, E_INC_C.compose(eta))
end

check "Theorem 11: 𝔈*_Γ is a submonoid — witnessing survives ⋄" do
  composite = E_ASSIGN_A.compose(E_INC_C).compose(E_ASSIGN_D)
  PROBES.each { |gamma| assert composite.witnessed_at?(gamma) }
end

check "Theorem 14: the lift agrees with the effect one level down — pr₁ ∘ f′ = f ∘ pr₁" do
  ec = Cordis::EffectContext.new(GAMMA0)
  successor, = ec.apply(E_INC_C)
  assert_equal E_INC_C.forward.call(GAMMA0), successor.state
end

check "Theorem 15: the lifted inverse recovers the state exactly — g′(Δ) = (γ, φ ∘ g ∘ f)" do
  ec = Cordis::EffectContext.new(GAMMA0)
  successor, lifted_inverse = ec.apply(E_INC_C)
  reverted = lifted_inverse.call(successor)
  assert_equal GAMMA0, reverted.state
  assert reverted.sound?(GAMMA0) # the soundness invariant is preserved in every case
end

check "Theorem 16: LIFO revert recovers every intermediate state, invariant throughout" do
  effects = [E_ASSIGN_A, E_INC_C, E_ASSIGN_D, assign(:b, 9)]
  ec = Cordis::EffectContext.new(GAMMA0)
  states = [GAMMA0]
  undos = []
  effects.each do |effect|
    ec, undo = ec.apply(effect)
    states << ec.state
    undos << undo
    assert ec.sound?(GAMMA0)
  end
  undos.reverse.each_with_index do |undo, i|
    ec = undo.call(ec)
    assert_equal states[states.length - 2 - i], ec.state
    assert ec.sound?(GAMMA0)
  end
  assert_equal GAMMA0, ec.state
end

puts "§3.1.3 — Independence and out-of-order withdrawal"

check "Definition 19: key-disjoint effects are independent; same-key effects are not" do
  assert Cordis::Independence.independent?(E_ASSIGN_A, E_INC_C, states: PROBES)
  assert Cordis::Independence.independent?(E_ASSIGN_A, E_ASSIGN_D, states: PROBES)
  assert !Cordis::Independence.independent?(E_ASSIGN_A, assign(:a, 7), states: PROBES)
end

check "Corollary 21: pairwise independent effects revert to γ₀ under every permutation" do
  effects = { a: E_ASSIGN_A, c: E_INC_C, d: E_ASSIGN_D }
  effects.values.combination(2) { |e1, e2| assert Cordis::Independence.independent?(e1, e2, states: PROBES) }

  ec0 = Cordis::EffectContext.new(GAMMA0)
  final = nil
  undos = {}
  effects.each do |key, effect|
    ec0, undo = ec0.apply(effect)
    undos[key] = undo
    final = ec0
  end
  undos.keys.permutation do |order|
    ec = order.reduce(final) { |acc, key| undos[key].call(acc) }
    assert_equal GAMMA0, ec.state
    assert ec.sound?(GAMMA0)
  end
end

puts "§3.2.1 — The coeffect context and its operations"

SIGMA0 = Cordis::CoeffectContext.new

check "Definition 22: preconditions — no double provision, no absent revocation, no absent read" do
  sigma = SIGMA0.bind(:db, "postgres://prod")
  assert_equal "postgres://prod", sigma.fetch(:db)
  assert_raises(Cordis::PreconditionViolation) { sigma.bind(:db, "again") }
  assert_raises(Cordis::PreconditionViolation) { sigma.unbind(:cache) }
  assert_raises(Cordis::PreconditionViolation) { SIGMA0.fetch(:db) }
end

check "Definition 23: set(k, v) is a witnessed effect on Σ — 𝔈*_Σ" do
  set_db = Cordis::Coeffects.set(:db, "postgres://prod")
  assert set_db.witnessed_at?(SIGMA0)
  sigma, revoke = set_db.call(SIGMA0)
  assert sigma.key?(:db)
  assert_equal SIGMA0, revoke.call(sigma)
end

check "eq. 23: an operation lift acts on the binding alone; its inverse maps the value it then finds" do
  counter = Cordis::Coeffect.new(:counter, value_type: Integer)
  counter.operation(:incr) { |amount, value| [value + amount, ->(w) { w - amount }, value + amount] }

  sigma = SIGMA0.bind(:counter, 5).bind(:label, "run")
  effect = counter.lift(:incr, 3)
  sigma2, inverse, outcome = effect.call(sigma)
  assert_equal 8, sigma2.fetch(:counter)
  assert_equal 8, outcome # b : B_a — the outcome of this application
  assert_equal "run", sigma2.fetch(:label) # the lift leaves every other key as it stands

  # The inverse applies g to whatever σ′ then holds at k — here after a
  # foreign effect on another key has moved the state.
  moved, = Cordis::Coeffects.set(:extra, true).call(sigma2)
  assert_equal 5, inverse.call(moved).fetch(:counter)
end

check "eq. 22: outcomes are paired with each application, not with the lift" do
  counter = Cordis::Coeffect.new(:n).operation(:incr) { |k, v| [v + k, ->(w) { w - k }, v + k] }
  effect = counter.lift(:incr, 1)
  _, _, first = effect.call(SIGMA0.bind(:n, 10))
  _, _, second = effect.call(SIGMA0.bind(:n, 100))
  assert_equal [11, 101], [first, second] # re-application clobbers nothing
  assert effect.witnessed_at?(SIGMA0.bind(:n, 0)) # probing is harmless too
end

check "Independence in Σ: operation lifts at distinct keys are independent (Definition 19)" do
  counter = Cordis::Coeffect.new(:counter).operation(:incr) { |n, v| [v + n, ->(w) { w - n }, v + n] }
  gauge = Cordis::Coeffect.new(:gauge).operation(:scale) { |n, v| [v * n, ->(w) { w / n }, v * n] }
  states = [SIGMA0.bind(:counter, 5).bind(:gauge, 2), SIGMA0.bind(:counter, 0).bind(:gauge, 8)]
  incr = counter.lift(:incr, 3)
  scale = gauge.lift(:scale, 2)
  assert Cordis::Independence.independent?(incr, scale, states: states)
end

check "Independence tolerates partiality: an undefined sample point yields no generator" do
  states = [SIGMA0, SIGMA0.bind(:a, 0)] # set(:a, 1) is undefined at the second state
  set_a = Cordis::Coeffects.set(:a, 1)
  set_b = Cordis::Coeffects.set(:b, 2)
  assert Cordis::Independence.independent?(set_a, set_b, states: states)
end

puts "§3.2.2 — Satisfaction and notification"

check "eq. 24: σ ⊨ d — satisfaction is membership of every declared key" do
  sigma = SIGMA0.bind(:log, :stdout).bind(:db, :sqlite)
  assert sigma.satisfies?([:log])
  assert sigma.satisfies?(%i[log db])
  assert !sigma.satisfies?(%i[log cache])
  assert sigma.satisfies?([]) # the empty specification is always satisfied
end

check "Definition 26: notify_d classifies every transition — the full truth table" do
  spec = %i[log]
  absent = SIGMA0
  present = SIGMA0.bind(:log, :stdout)
  assert_equal :activating,   Cordis::Coeffects.notify(spec, absent, present)
  assert_equal :deactivating, Cordis::Coeffects.notify(spec, present, absent)
  assert_equal :neutral,      Cordis::Coeffects.notify(spec, absent, absent.bind(:other, 1))
  assert_equal :neutral,      Cordis::Coeffects.notify(spec, present, present.bind(:other, 1))
end

puts "§3.2.3 — Isolation"

check "Definitions 28/29: isolation resolves the same key to different values per realm" do
  base = Cordis::IsolatedContext.new({}, { db: "postgres://prod" })
  sandboxed = base.isolate(:db, :sandbox).bind(:db, "sqlite://memory")
  assert_equal "sqlite://memory", sandboxed.fetch(:db) # resolved through ρ(db) = :sandbox
  assert_equal "postgres://prod", base.fetch(:db)      # the shared table is untouched
  assert_equal "postgres://prod", sandboxed.table[:db] # the prod binding still sits underneath
end

check "Definition 27: isolate is a derived realization — no inverse to track, recovery discards" do
  base = Cordis::IsolatedContext.new({}, { db: "postgres://prod" })
  derived = base.isolate(:db, :sandbox)
  assert_equal base.table, derived.table # fresh context, table shared, ρ adjusted
  assert_equal :sandbox, derived.resolve(:db)
  assert_equal :db, base.resolve(:db) # a key outside dom(ρ) resolves to its own realm
end

puts "§3.2.3 — Interception"

check "Definitions 30/31: metadata merges right-biased — the context constrains the component" do
  fs = Cordis::InterceptedContext.new.bind(:fs, ->(meta) { "fs(mode=#{meta[:mode] || "rw"})" })
  assert_equal "fs(mode=rw)", fs.fetch(:fs) # ε_k — empty metadata by default
  sandboxed = fs.intercept(:fs, { mode: "ro" })
  assert_equal "fs(mode=ro)", sandboxed.fetch(:fs, { mode: "rw" }) # ι(k) overrides the declaration μ
  assert_equal "fs(mode=rw)", fs.fetch(:fs, { mode: "rw" })        # derived: the original is untouched
  assert_raises(Cordis::PreconditionViolation) { fs.bind(:fs, ->(_) {}) }
end

puts "§3.3.2 — Observational equivalence and commutative keys"

check "Definition 33: states relate when they bind the same keys to ≈_k-related values" do
  related = lambda do |a, b, equivalences|
    a.domain.sort == b.domain.sort &&
      a.domain.all? { |k| equivalences.fetch(k, :==).to_proc.call(a.fetch(k), b.fetch(k)) }
  end
  routes_as_set = ->(x, y) { x.keys.sort == y.keys.sort }
  one = Cordis::CoeffectContext.new.bind(:routes, { "a" => true, "b" => true })
  two = Cordis::CoeffectContext.new.bind(:routes, { "b" => true, "a" => true })
  assert related.call(one, two, { routes: routes_as_set })
end

check "Definition 39 / Theorem 40 flavor: a table-valued key is commutative; an ordered chain is not" do
  routes = Cordis::Coeffect.new(:routes)
  routes.operation(:add) { |name, table| [table.merge(name => true), ->(w) { w.reject { |k, _| k == name } }, name] }
  chain = Cordis::Coeffect.new(:chain)
  chain.operation(:push) { |name, list| [list + [name], ->(w) { w[0...-1] }, name] }

  states = [Cordis::CoeffectContext.new.bind(:routes, {}).bind(:chain, []),
            Cordis::CoeffectContext.new.bind(:routes, { "c" => true }).bind(:chain, ["c"])]

  # Two registrations in either order leave a table that answers every test
  # alike — operations of a commutative key are independent of each other…
  assert Cordis::Independence.independent?(routes.lift(:add, "a"), routes.lift(:add, "b"), states: states)
  # …whereas a middleware inserted before another sees a different request,
  # and neither order can be withdrawn without disturbing the other.
  assert !Cordis::Independence.independent?(chain.lift(:push, "a"), chain.lift(:push, "b"), states: states)
  # Theorem 40: operations at distinct keys are independent outright.
  assert Cordis::Independence.independent?(routes.lift(:add, "a"), chain.lift(:push, "b"), states: states)
end

puts "The reactive runtime — failure and precondition discipline (§3.2.1, §3.2.2)"

check "A failed activation produces no transition: effect rolled back, component inactive" do
  sys = Cordis::System.new
  bad = Cordis::Component.new("bad", requires: [:config]) do |ctx|
    ctx.provide(:partial, 1) # tracked, then recovered when the next line raises
    ctx.get(:missing)
  end
  sys.mount(bad)
  assert_raises(Cordis::PreconditionViolation) { sys.provide(:config, 1) }
  assert_equal [], sys.active
  assert_equal sys.initial, sys.context # nothing stranded — the invariant held
end

check "Mounting an already-mounted name is refused: its accumulator must never be orphaned" do
  sys = Cordis::System.new
  component = Cordis::Component.new("c")
  sys.mount(component)
  assert_raises(Cordis::PreconditionViolation) { sys.mount(component) }
end

check "A component named \"host\" is an ordinary component, not the host pseudo-entry" do
  sys = Cordis::System.new
  impostor = Cordis::Component.new("host", requires: [:cfg]) { |ctx| ctx.provide(:derived, true) }
  sys.mount(impostor)
  sys.provide(:cfg, 1)
  assert_equal ["host"], sys.active # it reacts like any other component
  sys.revoke(:cfg)
  assert_equal [], sys.active
  assert_equal sys.initial, sys.context
end

puts
if FAILURES.empty?
  puts "All checks passed."
else
  puts "#{FAILURES.length} check(s) FAILED: #{FAILURES.join("; ")}"
  exit 1
end
