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
add_outcome = calc.add(3)
puts add_outcome
puts

puts "-> calc.multiply(4)"
multiply_outcome = calc.multiply(4)
puts multiply_outcome
puts

puts "-> calc.sqrt(latest_result)"
latest_result = multiply_outcome.value
puts calc.sqrt(latest_result)
puts

puts "-> calc.runtime_context[:memory] || calc.runtime_context[:value]"
puts(calc.runtime_context[:memory] || calc.runtime_context[:value])
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
history_outcome = calc.history
history_value = history_outcome.ok? ? history_outcome.value : nil
history_value ||= calc.runtime_context[:conversation_history]
puts history_value.inspect
