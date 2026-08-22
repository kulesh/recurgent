# frozen_string_literal: true

# Declarative configuration over the fiber calculus (§5.2.1): the
# orchestrator edits a persistent record of entries (Definition 74); the
# loader reconciles the running system to it, and Theorem 73 guarantees the
# result is the one a from-scratch load of the final record would produce.
#
# Run: ruby demo_reconcile.rb

require_relative "cordis_loader"

def entry(id, builder, config: nil, disabled: false)
  Cordis::Loader::Entry.new(id: id, builder: builder, config: config, disabled: disabled)
end

CONFIG = ->(_) { Cordis::Calculus::Component.build(:config_provider, provide: [:config]) { |c| c.set(:config, { prefix: "[core]" }) } }
LOGGER = lambda do |version|
  Cordis::Calculus::Component.build(:logger, inject: [:config], provide: [:log]) do |c|
    c.set(:log) { |reads| "#{reads[:config][:prefix]} v#{version}" }
  end
end
METRICS = lambda do |_|
  Cordis::Calculus::Component.build(:metrics, inject: [:log], provide: [:count]) do |c|
    c.set(:count) { |reads| "count via #{reads[:log]}" }
  end
end
DASH = lambda do |_|
  Cordis::Calculus::Component.build(:dashboard, inject: %i[log count], provide: [:render]) do |c|
    c.set(:render) { |reads| "render(#{reads[:count]})" }
  end
end

def tree(logger_version:, dash_disabled: false)
  [entry("config", CONFIG), entry("logger", LOGGER, config: logger_version),
   entry("metrics", METRICS), entry("dash", DASH, disabled: dash_disabled)]
end

loader = Cordis::Loader::Reconciler.new(Cordis::Calculus::Machine.new(seed: 42))

puts "— Reconcile v1: four entries, dependency order discovered reactively (Theorem 63)"
loader.reconcile(tree(logger_version: "1.0"))
puts "  render: #{loader.machine.sigma[:render]}"

puts "— Reconcile v2: logger config 1.0 → 2.0 (entry rebuilt), dash disabled (fiber unloaded)"
loader.reconcile(tree(logger_version: "2.0", dash_disabled: true))
puts "  count:  #{loader.machine.sigma[:count]}"
puts "  render? #{loader.machine.sigma.key?(:render)}"

puts "— Reconcile v3: dash re-enabled — reloads against the new logger, nothing else moves"
loader.reconcile(tree(logger_version: "2.0"))
puts "  render: #{loader.machine.sigma[:render]}"

puts "— The licence (Theorem 73): the reconciled system equals a from-scratch load of v3"
fresh = Cordis::Loader::Reconciler.new(Cordis::Calculus::Machine.new(seed: 7))
fresh.reconcile(tree(logger_version: "2.0"))
raise "reconciliation diverged from static assembly!" unless fresh.machine.snapshot == loader.machine.snapshot

puts "  snapshots equal — dynamic history left no trace"

puts "— Reconcile ∅: every entry withdrawn; the registry empties"
loader.reconcile([])
raise "fibers remain!" unless loader.machine.fibers.empty?
raise "context remains!" unless loader.machine.sigma.empty?

puts "  registry empty, derived context empty"

puts
puts "Rule trace of the v1→v2 reconciliation window (each line is one rule application):"
loader.machine.trace.each { |rule, name| puts "  #{rule.to_s.ljust(9)} #{name}" }
