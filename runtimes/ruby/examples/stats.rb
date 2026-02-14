#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/recurgent"

MODEL = Agent::DEFAULT_MODEL

puts "=== Statistics Calculator ==="
puts "Model: #{MODEL}"
puts
puts "No stats gem. No numpy. No formulas."
puts "Just a name and some data. The LLM figures out the rest."
puts

stats = Agent.for("statistics calculator", model: MODEL)

puts "-> stats.data = [12, 15, 18, 22, 15, 30, 18, 15, 25, 42]"
stats.data = [12, 15, 18, 22, 15, 30, 18, 15, 25, 42]
puts

puts "-> stats.mean"
puts stats.mean
puts

puts "-> stats.median"
puts stats.median
puts

puts "-> stats.mode"
puts stats.mode.inspect
puts

puts "-> stats.standard_deviation"
puts stats.standard_deviation
puts

puts "-> stats.percentile(90)"
puts stats.percentile(90)
puts

puts "-> stats.outliers"
puts stats.outliers.inspect
puts

puts "-> stats.histogram(buckets: 5)"
puts stats.histogram(buckets: 5).inspect
puts

puts "-> stats.summary"
puts stats.summary.inspect
