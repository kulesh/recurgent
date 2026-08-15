# frozen_string_literal: true

# Hot module replacement, the paper's capstone scenario (§1.2, §5.2.2), on the
# Cordis runtime: components declare coeffect specifications (Definition 25),
# every context transition is classified against them (Definition 26), and
# unloading recovers the shared context exactly (revertible effects, §3.1).
#
# Run: ruby demo_hot_swap.rb

require_relative "cordis"

system = Cordis::System.new

# A component's requires is its coeffect specification d ∈ 𝔇_Σ (Definition 25);
# its activation block performs witnessed set effects (Definition 23), each
# inverse joining the component's own accumulator (§3.1.3).
logger_v1 = Cordis::Component.new("logger@1.0", requires: [:config]) do |ctx|
  prefix = ctx.get(:config).fetch(:prefix)
  ctx.provide(:log, ->(msg) { "#{prefix} #{msg}" })
end

logger_v2 = Cordis::Component.new("logger@2.0", requires: [:config]) do |ctx|
  prefix = ctx.get(:config).fetch(:prefix)
  ctx.provide(:log, ->(msg) { "#{prefix} ⚡ #{msg.upcase}" })
end

metrics = Cordis::Component.new("metrics", requires: [:log]) do |ctx|
  log = ctx.get(:log)
  ctx.provide(:count_events, ->(n) { log.call("counted #{n} events") })
end

dashboard = Cordis::Component.new("dashboard", requires: %i[log count_events]) do |ctx|
  count = ctx.get(:count_events)
  ctx.provide(:render, -> { "dashboard | #{count.call(42)}" })
end

puts "— Mounting components (none can activate yet: their specifications are unsatisfied)"
system.mount(metrics).mount(dashboard).mount(logger_v1)
raise "nothing should be active" unless system.active.empty?

puts "— Host provides :config — one transition, and the whole tree activates reactively"
system.provide(:config, { prefix: "[core]" })
puts "  active: #{system.active.join(", ")}"
puts "  render: #{system.context.fetch(:render).call}"

puts "— Hot swap: unmount logger@1.0 (dependents deactivate before :log is withdrawn, §3.2.2)"
system.unmount("logger@1.0")
puts "  active: #{system.active.join(", ")}"

puts "— Mount logger@2.0 — dependents reactivate against the new provider"
system.mount(logger_v2)
puts "  active: #{system.active.join(", ")}"
puts "  render: #{system.context.fetch(:render).call}"

puts "— Host withdraws :config: a selective revert (Corollary 21) cascades every deactivation"
system.revoke(:config)
puts "  active: #{system.active.join(", ")}"

puts "— Unmount everything; temporal composability demands σ = σ₀ exactly"
%w[metrics dashboard logger@2.0].each { |name| system.unmount(name) }
raise "context was not recovered!" unless system.context == system.initial

puts "  recovered: context == initial context (#{system.context.table.inspect})"

puts
puts "Transition trace (every line is a classified transition or lifecycle event):"
system.trace.each { |line| puts "  #{line}" }
