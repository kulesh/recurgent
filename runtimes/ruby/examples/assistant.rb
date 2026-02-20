#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/recurgent"

MODEL = Agent::DEFAULT_MODEL

ASSISTANT_ROLE_PROFILE = {
  role: "personal assistant that remembers conversation history",
  version: 1,
  constraints: {
    conversation_history_slot: {
      kind: :shared_state_slot,
      methods: %w[ask],
      mode: :prescriptive,
      canonical_key: :conversation_history
    }
  }
}.freeze

Agent.configure_runtime(
  role_profile_shadow_mode_enabled: true,
  role_profile_enforcement_enabled: true
)

puts "=== Personal Assistant ==="
puts "Model: #{MODEL}"
puts "Type 'quit' or 'exit' to stop.\n\n"

assistant = Agent.for(
  "personal assistant that remembers conversation history",
  model: MODEL,
  debug: true,
  role_profile: ASSISTANT_ROLE_PROFILE
)

loop do
  print "> "
  input = $stdin.gets&.chomp
  break if input.nil? || %w[quit exit].include?(input.downcase)
  next if input.strip.empty?

  puts assistant.ask(input)
  puts
end
