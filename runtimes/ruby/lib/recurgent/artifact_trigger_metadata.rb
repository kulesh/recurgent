# frozen_string_literal: true

class Agent
  # Agent::ArtifactTriggerMetadata — failure-trigger metadata for artifact generation history.
  module ArtifactTriggerMetadata
    private

    def _artifact_trigger_failure_metadata(state)
      stage = state.latest_failure_stage.to_s
      return {} if stage.empty?

      metadata = {
        "trigger_stage" => stage,
        "trigger_error_class" => state.latest_failure_class.to_s,
        "trigger_error_message" => state.latest_failure_message.to_s
      }
      attempt_id = Array(state.attempt_failures).last&.fetch(:attempt_id, nil)
      metadata["trigger_attempt_id"] = attempt_id unless attempt_id.nil?
      metadata
    end
  end
end
