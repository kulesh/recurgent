# frozen_string_literal: true

class Agent
  # Agent::Delegation — delegation intent inference, validation, and option filtering.
  module Delegation
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

    # -- Intent inference & validation -----------------------------------------

    def _validate_delegation_contract_intent_signature!(value)
      return if value.nil?
      return if value.is_a?(String) && !value.strip.empty?

      raise ArgumentError, "delegation_contract[:intent_signature] must be a non-empty String when provided"
    end

    def _resolve_delegate_intent_signature(explicit_signature)
      explicit = explicit_signature.to_s.strip
      return explicit unless explicit.empty?

      _inferred_delegate_intent_signature
    end

    def _inferred_delegate_intent_signature
      context = self.class.current_outcome_context
      method_name = context[:method_name].to_s.strip
      return nil if method_name.empty?

      parts = [method_name]
      args_segment = _delegate_intent_args_segment(context[:args])
      kwargs_segment = _delegate_intent_kwargs_segment(context[:kwargs])
      parts << args_segment unless args_segment.empty?
      parts << kwargs_segment unless kwargs_segment.empty?
      parts.join(": ")
    end

    def _delegate_intent_args_segment(args)
      preview = Array(args).first(2).map { |value| _delegate_intent_segment(value) }.reject(&:empty?)
      return "" if preview.empty?

      "args=#{preview.join(" | ")}"
    end

    def _delegate_intent_kwargs_segment(kwargs)
      return "" unless kwargs.is_a?(Hash) && !kwargs.empty?

      "kwargs=#{kwargs.keys.first(3).map(&:to_s).join(",")}"
    end

    def _delegate_intent_segment(value)
      text = value.to_s.strip
      return "" if text.empty?

      text[0, 120]
    end

    # -- Option filtering ------------------------------------------------------

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
