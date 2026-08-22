# frozen_string_literal: true

# Executable checks for the calculus of §4 and the loader of §5.2, run over
# randomized schedules: the calculus names no scheduler (§4.2), so each check
# that quantifies over schedules samples several seeds.
#
# Run: ruby calculus_checks.rb

require_relative "cordis_loader"

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

SEEDS = (1..8).to_a.freeze

# --- the component fixture: a small dependency tree -------------------------
#
#   config_provider ──:config──▶ logger ──:log──▶ metrics ──:count──▶ dashboard
#
# Every effect is a provision into the fiber's own table (Definition 48).

def config_provider
  Cordis::Calculus::Component.build(:config_provider, provide: [:config]) do |c|
    c.set(:config, { prefix: "[core]" })
  end
end

def logger(version = "1.0")
  Cordis::Calculus::Component.build(:logger, inject: [:config], provide: [:log]) do |c|
    c.set(:log) { |reads| "#{reads[:config][:prefix]} v#{version}" }
  end
end

def metrics
  Cordis::Calculus::Component.build(:metrics, inject: [:log], provide: [:count]) do |c|
    c.set(:count) { |reads| "count via #{reads[:log]}" }
  end
end

def dashboard
  Cordis::Calculus::Component.build(:dashboard, inject: %i[log count], provide: [:render]) do |c|
    c.set(:render) { |reads| "render(#{reads[:count]})" }
  end
end

def machine_with_tree(seed:)
  machine = Cordis::Calculus::Machine.new(seed: seed)
  machine.o_insert("dash", dashboard)
  machine.o_insert("metrics", metrics)
  machine.o_insert("logger", logger)
  machine.o_insert("config", config_provider)
  machine
end

puts "§4.2 — The base lifecycle, driven reactively"

check "Insertion order is irrelevant: every schedule activates the whole tree (Definition 46)" do
  SEEDS.each do |seed|
    machine = machine_with_tree(seed: seed).run
    machine.fibers.each_value { |fiber| assert_equal :active, fiber.state }
    assert machine.sigma.key?(:render)
    assert machine.quiet?
  end
end

check "Theorem 59 (Preservation): well-formedness holds at every step of every schedule" do
  SEEDS.each do |seed|
    machine = machine_with_tree(seed: seed)
    steps = 0
    loop do
      assert machine.well_formed?, "well-formedness broken at step #{steps} (seed #{seed})"
      break unless machine.step

      steps += 1
    end
  end
end

puts "§4.3.1 — Withdrawal: the guard on L-Unload"

check "Theorem 63 (Ordering): a provider unloads only after every dependent that resolved to it" do
  SEEDS.each do |seed|
    machine = machine_with_tree(seed: seed).run
    machine.o_retire("logger")
    machine.run
    unloads = machine.trace.filter_map { |rule, name| name if rule == :l_unload }
    %w[metrics dash].each do |dependent|
      assert unloads.index(dependent) < unloads.index("logger"),
             "#{dependent} must reach Inactive before logger's withdrawal takes effect (seed #{seed})"
    end
    assert_equal :inactive, machine.fibers["logger"].state
    assert machine.sigma.empty? == false || machine.sigma.key?(:config)
  end
end

check "L-Leave stops provision one step early: an Unloading fiber is outside σ_γ (eq. 40)" do
  machine = machine_with_tree(seed: 3).run
  machine.o_retire("logger")
  machine.l_leave("logger")
  assert !machine.sigma.key?(:log) # stopped providing…
  assert machine.fibers["logger"].table.key?(:log) # …while its bindings are all still in place
end

puts "§4.4.4 — Progress"

check "Theorem 66: every maximal sequence of lifecycle steps ends in a quiescent state" do
  SEEDS.each do |seed|
    machine = machine_with_tree(seed: seed).run
    machine.o_retire("config")
    machine.run # raises if the guard deadlocks or the sequence diverges
    assert machine.quiet?
    machine.fibers.each_value { |fiber| assert_equal :inactive, fiber.state }
  end
end

puts "§4.4.2 — Recovery"

check "Corollary 62 (Terminal recovery): a departing fiber's contribution is nothing" do
  SEEDS.each do |seed|
    machine = machine_with_tree(seed: seed).run
    before = machine.sigma.dup
    machine.o_insert("extra", Cordis::Calculus::Component.build(:extra, inject: [:log], provide: [:extra]) do |c|
      c.set(:extra, 1)
    end)
    machine.run
    assert machine.sigma.key?(:extra)
    machine.o_retire("extra")
    machine.run
    machine.o_remove("extra")
    assert_equal before, machine.sigma
    assert !machine.fibers.key?("extra")
  end
end

puts "§4.3.2/§4.3.4 — Registration, iteration, failure"

check "Definition 47: unloading a parent retires what its iterations registered, one level at a time" do
  child = Cordis::Calculus::Component.build(:child, provide: [:child_svc]) { |c| c.set(:child_svc, true) }
  parent = Cordis::Calculus::Component.build(:parent, provide: [:parent_svc]) do |c|
    c.set(:parent_svc, true)
    c.register(child)
  end
  machine = Cordis::Calculus::Machine.new(seed: 5)
  machine.o_insert("parent", parent)
  machine.run
  assert machine.sigma.key?(:child_svc)
  machine.o_retire("parent")
  machine.run
  child_fiber = machine.fibers["parent/child#0"]
  assert child_fiber.retired && child_fiber.state == :inactive
  assert machine.sigma.empty?
end

check "L-Raise (§4.3.4): a failing transition recovers, records the error, and obstructs nothing" do
  bad = Cordis::Calculus::Component.build(:bad, provide: [:bad_svc]) do |c|
    c.set(:bad_svc, true)
    c.fail!("port already bound")
  end
  machine = machine_with_tree(seed: 2)
  machine.o_insert("bad", bad)
  machine.run
  fiber = machine.fibers["bad"]
  assert fiber.failed? # Inactive(ξ) — the lifecycle is not re-entered from an error outcome
  assert_equal "port already bound", fiber.outcome
  assert fiber.table.empty? # arrived having installed nothing
  assert machine.sigma.key?(:render) # siblings keep running (failure is per-fiber)
  assert machine.quiet?
end

puts "§4.4.5 — Confluence"

check "Theorem 73: every schedule of the same orchestration steps reaches the same quiescent state" do
  snapshots = SEEDS.map { |seed| machine_with_tree(seed: seed).run.snapshot }
  snapshots.each { |snap| assert_equal snapshots.first, snap }
end

check "Theorem 73 (dynamic history leaves no trace): load–unload–reload ≈ statically assembled" do
  # Take a system through a swap and back down to the target composition…
  eventful = machine_with_tree(seed: 4).run
  eventful.o_retire("logger")
  eventful.run
  eventful.o_remove("logger")
  eventful.o_insert("logger", logger("2.0"))
  eventful.run
  # …and assemble the target composition from scratch.
  fresh = Cordis::Calculus::Machine.new(seed: 9)
  fresh.o_insert("dash", dashboard)
  fresh.o_insert("metrics", metrics)
  fresh.o_insert("logger", logger("2.0"))
  fresh.o_insert("config", config_provider)
  fresh.run
  assert_equal fresh.snapshot, eventful.snapshot
end

puts "§5.2.1 — Declarative configuration and reconciliation"

def entry(id, builder, config: nil, disabled: false)
  Cordis::Loader::Entry.new(id: id, builder: builder, config: config, disabled: disabled)
end

LOGGER_BUILDER = ->(config) { logger(config || "1.0") }
STATIC = { "config" => ->(_) { config_provider }, "metrics" => ->(_) { metrics }, "dash" => ->(_) { dashboard } }.freeze

def entries_for(logger_config:, dash_disabled: false)
  [entry("config", STATIC["config"]), entry("logger", LOGGER_BUILDER, config: logger_config),
   entry("metrics", STATIC["metrics"]), entry("dash", STATIC["dash"], disabled: dash_disabled)]
end

check "Reconciliation lands where a from-scratch load of the final configuration would (Theorem 73)" do
  reconciler = Cordis::Loader::Reconciler.new(Cordis::Calculus::Machine.new(seed: 6))
  reconciler.reconcile(entries_for(logger_config: "1.0"))
  reconciler.reconcile(entries_for(logger_config: "2.0", dash_disabled: true)) # config change + disable

  fresh = Cordis::Loader::Reconciler.new(Cordis::Calculus::Machine.new(seed: 7))
  fresh.reconcile(entries_for(logger_config: "2.0", dash_disabled: true))

  assert_equal fresh.machine.snapshot, reconciler.machine.snapshot
  assert_equal "count via [core] v2.0", reconciler.machine.sigma[:count]
  assert !reconciler.machine.sigma.key?(:render) # dash disabled
end

check "Clearing disabled reloads the entry (Definition 74 per-field dispatch)" do
  reconciler = Cordis::Loader::Reconciler.new(Cordis::Calculus::Machine.new(seed: 8))
  reconciler.reconcile(entries_for(logger_config: "1.0", dash_disabled: true))
  assert !reconciler.machine.sigma.key?(:render)
  reconciler.reconcile(entries_for(logger_config: "1.0", dash_disabled: false))
  assert_equal "render(count via [core] v1.0)", reconciler.machine.sigma[:render]
end

puts "§5.2.2 — Hot module replacement, the pure phases"

IMPORTS = {
  "app" => %w[ui net],
  "ui" => %w[theme],
  "cycle_x" => %w[cycle_a],
  "cycle_a" => %w[cycle_b],
  "cycle_b" => %w[cycle_a]
}.freeze

check "Algorithm 8: accepts spread along imports; cycles default to declined" do
  accepted, declined = Cordis::Loader::HMR.classify(%w[theme], %w[net], IMPORTS)
  assert_equal %w[theme], accepted
  assert declined.include?("net")

  accepted, declined = Cordis::Loader::HMR.classify(%w[cycle_x], [], IMPORTS)
  assert accepted.include?("cycle_x")
  assert declined.include?("cycle_a") && declined.include?("cycle_b") # caught in an import cycle
end

check "Algorithm 9: an entry is stale exactly when its dependency tree reaches a changed module" do
  accepted, declined = Cordis::Loader::HMR.classify(%w[theme], %w[net], IMPORTS)
  stale, folded = Cordis::Loader::HMR.detect(%w[app cycle_x], accepted, declined, IMPORTS)
  assert_equal %w[app], stale # app reaches theme through ui; cycle_x reaches no change
  assert folded.include?("ui") && folded.include?("app") # the tree is folded into accepted
  assert !folded.include?("net") # declined is a boundary
end

puts
if FAILURES.empty?
  puts "All checks passed."
else
  puts "#{FAILURES.length} check(s) FAILED: #{FAILURES.join("; ")}"
  exit 1
end
