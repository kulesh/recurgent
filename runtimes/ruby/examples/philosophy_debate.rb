#!/usr/bin/env ruby
# frozen_string_literal: true

# Same recursive delegation pattern as debate.rb, with a different domain.
# Three philosophers from distinct traditions discuss a timeless question.
# Each round, they respond to what was said before — arguments sharpen
# because the history accumulates.

require_relative "../lib/recurgent"

debate = Agent.for("philosophy_symposium_host", verbose: true)

puts debate.host(
  question: "What is the good life?",
  tool_contract_guidance: {
    purpose: "Each philosopher should contribute one round-specific argument and engage prior responses",
    deliverable: {
      type: "object",
      required: %w[position engagement synthesis]
    },
    acceptance: [
      { assert: "includes explicit position" },
      { assert: "engages at least one other thinker's claim" }
    ],
    failure_policy: {
      on_error: "continue_with_partial_symposium",
      retry_budget: 1
    }
  },
  thinkers: [
    "Stoic philosopher in the tradition of Marcus Aurelius",
    "Epicurean philosopher in the tradition of Epicurus",
    "Existentialist in the tradition of Simone de Beauvoir"
  ],
  rounds: 3
)

puts debate.debate_takeaways(10)
