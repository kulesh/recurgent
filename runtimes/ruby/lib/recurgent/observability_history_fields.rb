# frozen_string_literal: true

class Agent
  # Agent::ObservabilityHistoryFields — conversation-history observability field mapping.
  module ObservabilityHistoryFields
    private

    def _core_history_fields(log_context)
      {
        history_record_appended: log_context[:history_record_appended],
        conversation_history_size: log_context[:conversation_history_size],
        history_access_detected: log_context[:history_access_detected],
        history_query_patterns: log_context[:history_query_patterns]
      }
    end
  end
end
