#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/recurgent"

MODEL = Agent::DEFAULT_MODEL

puts "=== Personal Assistant ==="
puts "Model: #{MODEL}"
puts "Type 'quit' or 'exit' to stop.\n\n"

assistant = Agent.for(
  "personal assistant that remembers conversation history",
  model: MODEL,
  debug: true
)

loop do
  print "> "
  input = $stdin.gets&.chomp
  break if input.nil? || %w[quit exit].include?(input.downcase)
  next if input.strip.empty?

  puts assistant.ask(input)
  puts
end
