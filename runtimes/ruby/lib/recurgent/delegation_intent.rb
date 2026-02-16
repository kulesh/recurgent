# frozen_string_literal: true

class Agent
  # Agent::DelegationIntent — infers and validates delegation intent signatures.
  module DelegationIntent
    private

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
  end
end
