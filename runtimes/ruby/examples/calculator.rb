#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/recurgent"

MODEL = Agent::DEFAULT_MODEL

puts "=== Calculator ==="
puts "Model: #{MODEL}"
puts
puts "No Math module. No formulas. No operator overloading."
puts "Just a name and method calls. The LLM figures out the rest."
puts

calc = Agent.for("calculator", model: MODEL)

puts "-> calc.memory = 5"
calc.memory = 5
puts

puts "-> calc.add(3)"
puts calc.add(3)
puts

puts "-> calc.multiply(4)"
puts calc.multiply(4)
puts

puts "-> calc.memory"
puts calc.memory
puts

puts "-> calc.sqrt(144)"
puts calc.sqrt(144)
puts

puts "-> calc.factorial(10)"
puts calc.factorial(10)
puts

puts "-> calc.convert(100, from: 'celsius', to: 'fahrenheit')"
puts calc.convert(100, from: "celsius", to: "fahrenheit")
puts

puts "-> calc.solve('2x + 5 = 17')"
puts calc.solve("2x + 5 = 17")
puts

puts "-> calc.history"
puts calc.history.inspect
