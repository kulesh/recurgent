# frozen_string_literal: true

class Agent
  # Agent::DelegationOptions — tolerant filtering for delegate() kwargs.
  # Keep non-runtime metadata from crashing Agent.for option parsing.
  module DelegationOptions
    AGENT_RUNTIME_OPTION_KEYS = %i[
      model
      provider
      verbose
      log
      debug
      max_generation_attempts
      guardrail_recovery_budget
      fresh_outcome_repair_budget
      provider_timeout_seconds
      delegation_budget
      delegation_contract
      delegation_contract_source
      trace_id
    ].freeze

    private

    def _partition_delegate_runtime_options(options)
      runtime_options = {}
      ignored_options = {}
      options.each do |key, value|
        if AGENT_RUNTIME_OPTION_KEYS.include?(key.to_sym)
          runtime_options[key] = value
        else
          ignored_options[key] = value
        end
      end
      [runtime_options, ignored_options]
    end

    def _warn_ignored_delegate_options(role:, ignored_options:)
      return unless @debug

      warn(
        "[AGENT DELEGATE OPTION IGNORE #{@role}->#{role}] " \
        "ignored non-runtime options: #{ignored_options.keys.map(&:to_s).sort.join(", ")}"
      )
    end
  end
end
