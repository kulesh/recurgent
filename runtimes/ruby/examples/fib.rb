#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/recurgent"

puts "=== Calculate Fibonacci ==="
puts "No Math module. No formulas. No operator overloading."
puts "Just a name and method calls. The LLM figures out the rest."
puts

fcalc = Agent.for("fibonacci_calculator")
puts fcalc.fibonacci(1000)
