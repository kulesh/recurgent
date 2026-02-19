# frozen_string_literal: true

class Agent
  # Agent::Authority — enforcement of observe/propose/enact boundaries for mutation paths.
  module Authority
    private

    def _proposal_mutation_allowed?(actor:)
      return true unless @runtime_config.fetch(:authority_enforcement_enabled, true)

      maintainers = Array(@runtime_config[:authority_maintainers]).map { |entry| entry.to_s.downcase }.reject(&:empty?)
      return false if maintainers.empty?

      maintainers.include?(actor.to_s.downcase)
    end

    def _proposal_actor(actor)
      candidate = actor.to_s.strip
      return candidate unless candidate.empty?

      ENV.fetch("USER", "unknown")
    end

    def _authority_denied_outcome(method_name:, actor:, action:)
      Outcome.error(
        error_type: "authority_denied",
        error_message: "Actor '#{actor}' is not authorized to #{action} proposal artifacts.",
        retriable: false,
        tool_role: @role,
        method_name: method_name,
        metadata: {
          actor: actor,
          action: action,
          authority: {
            observe: true,
            propose: true,
            enact: false
          }
        }
      )
    end
  end
end
