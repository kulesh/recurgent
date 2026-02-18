#!/usr/bin/env ruby
# frozen_string_literal: true

# Recursive delegation: the host receives panelist names as strings, creates
# child Agents for each, and runs a multi-round debate. One user-facing
# method call triggers (panelists × rounds) + 1 LLM calls.
#
# The host's LLM-generated code creates the child Agents — the user never
# builds them. That's the delegation: the LLM decides how to instantiate and
# orchestrate the panel.

require_relative "../lib/recurgent"

debate = Agent.for("debate_show_host", verbose: true)

puts debate.moderate(
  topic: "Should programming languages have garbage collection?",
  tool_contract_guidance: {
    purpose: "Each panelist should provide a perspective tied to their role in this round",
    deliverable: {
      type: "object",
      required: %w[stance rationale rebuttal]
    },
    acceptance: [
      { assert: "includes clear stance" },
      { assert: "includes rationale grounded in the panelist perspective" }
    ],
    failure_policy: {
      on_error: "continue_with_partial_panel",
      retry_budget: 1
    }
  },
  panelists: [
    "systems programmer who values performance above all",
    "web developer who prizes productivity and safety",
    "security engineer focused on memory safety vulnerabilities",
    "Dennis Ritchie, creator of C, speaking from the beyond",
    "philosopher questioning the nature of ownership and responsibility"
  ],
  rounds: 3
)
puts debate.moderation_overview(format: :markdown)
