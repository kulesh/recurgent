# frozen_string_literal: true

class Agent
  # Agent::ObservabilityHistoryFields — conversation-history observability field mapping.
  module ObservabilityHistoryFields
    private

    def _core_history_fields(log_context)
      {
        history_record_appended: log_context[:history_record_appended],
        conversation_history_size: log_context[:conversation_history_size],
        content_store_write_applied: log_context[:content_store_write_applied],
        content_store_write_ref: log_context[:content_store_write_ref],
        content_store_write_kind: log_context[:content_store_write_kind],
        content_store_write_bytes: log_context[:content_store_write_bytes],
        content_store_write_digest: log_context[:content_store_write_digest],
        content_store_write_skipped_reason: log_context[:content_store_write_skipped_reason],
        content_store_eviction_count: log_context[:content_store_eviction_count],
        content_store_read_hit_count: log_context[:content_store_read_hit_count],
        content_store_read_miss_count: log_context[:content_store_read_miss_count],
        content_store_read_refs: log_context[:content_store_read_refs],
        content_store_entry_count: log_context[:content_store_entry_count],
        content_store_total_bytes: log_context[:content_store_total_bytes],
        history_access_detected: log_context[:history_access_detected],
        history_query_patterns: log_context[:history_query_patterns]
      }
    end
  end
end
