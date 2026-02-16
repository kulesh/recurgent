# frozen_string_literal: true

class Agent
  # Agent::GuardrailBoundaryNormalization — user-boundary normalization for exhausted guardrail retries.
  module GuardrailBoundaryNormalization
    NORMALIZATION_POLICY = "guardrail_exhaustion_boundary_v1"
    USER_MESSAGE = "This request couldn't be completed after multiple attempts."

    private

    def _normalize_top_level_guardrail_exhaustion_payload(payload:, error:, call_context:)
      return payload unless payload[:error_type] == "guardrail_retry_exhausted"
      return payload unless _top_level_call_context?(call_context)

      metadata = payload[:metadata].is_a?(Hash) ? payload[:metadata].dup : {}
      metadata[:normalized] = true
      metadata[:normalization_policy] = NORMALIZATION_POLICY
      metadata[:guardrail_class] ||= "recoverable_guardrail"
      metadata[:guardrail_subtype] = metadata[:last_violation_subtype] || "unknown_guardrail_violation"
      metadata[:raw_error_message] ||= error.message.to_s

      payload.merge(
        error_message: USER_MESSAGE,
        metadata: metadata
      )
    end

    def _top_level_call_context?(call_context)
      return false unless call_context.is_a?(Hash)

      call_context.fetch(:depth, nil).to_i.zero?
    end
  end
end
