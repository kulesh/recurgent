# frozen_string_literal: true

class Agent
  # Agent::UserCorrectionSignals — deterministic top-level re-ask detection for utility corrections.
  module UserCorrectionSignals
    USER_CORRECTION_REASK_WINDOW_SECONDS = 180
    USER_CORRECTION_MIN_OVERLAP_RATIO = 0.67

    private

    def _capture_user_correction_state!(state, user_correction)
      detected = user_correction.is_a?(Hash) && user_correction["detected"] == true
      state.user_correction_detected = detected
      state.user_correction_signal = detected ? user_correction["signal"] : nil
      state.user_correction_reference_call_id = detected ? user_correction["correction_of_call_id"] : nil
    end

    def _detect_temporal_reask_user_correction(method_name:, state:, call_context:, timestamp:)
      return nil unless _eligible_reask_user_correction_call?(method_name: method_name, call_context: call_context)

      previous_event = _latest_pattern_memory_event(role: @role, method_name: method_name)
      return nil unless _temporal_reask_match?(previous_event, call_context: call_context, timestamp: timestamp)

      previous_patterns = _normalized_capability_patterns(previous_event["capability_patterns"])
      current_patterns = _normalized_capability_patterns(state.capability_patterns)
      if _near_identical_capability_patterns?(previous_patterns, current_patterns)
        return _temporal_reask_with_pattern_overlap(previous_event, previous_patterns, current_patterns)
      end

      return _temporal_reask_without_tooling(previous_event) if _no_tooling_reask?(previous_event, current_patterns, call_context)

      nil
    end

    def _temporal_reask_with_pattern_overlap(previous_event, previous_patterns, current_patterns)
      {
        "detected" => true,
        "signal" => "temporal_reask",
        "correction_of_call_id" => previous_event["call_id"].to_s,
        "matched_capability_patterns" => (current_patterns & previous_patterns)
      }
    end

    def _temporal_reask_without_tooling(previous_event)
      {
        "detected" => true,
        "signal" => "temporal_reask_no_tooling",
        "correction_of_call_id" => previous_event["call_id"].to_s,
        "matched_capability_patterns" => []
      }
    end

    def _eligible_reask_user_correction_call?(method_name:, call_context:)
      return false unless call_context.is_a?(Hash)
      return false unless call_context.fetch(:depth, nil).to_i.zero?
      return false if call_context.fetch(:trace_id, nil).to_s.empty?
      return false if method_name.to_s.strip.empty?

      true
    end

    def _latest_pattern_memory_event(role:, method_name:)
      _pattern_memory_recent_events(role: role, method_name: method_name, window: 1).last
    end

    def _temporal_reask_match?(previous_event, call_context:, timestamp:)
      return false unless previous_event.is_a?(Hash)
      return false unless previous_event.fetch("depth", nil).to_i.zero?
      return false unless previous_event.fetch("trace_id", nil).to_s == call_context.fetch(:trace_id, nil).to_s

      previous_recorded_at_ms = previous_event["recorded_at_ms"].to_i
      return false unless previous_recorded_at_ms.positive?

      elapsed_seconds = ((timestamp.to_f * 1000).to_i - previous_recorded_at_ms).to_f / 1000
      elapsed_seconds.between?(0, USER_CORRECTION_REASK_WINDOW_SECONDS)
    end

    def _near_identical_capability_patterns?(left_patterns, right_patterns)
      overlap = (left_patterns & right_patterns).length
      return false if overlap.zero?

      max_size = [left_patterns.length, right_patterns.length].max
      return false unless max_size.positive?

      (overlap.to_f / max_size) >= USER_CORRECTION_MIN_OVERLAP_RATIO
    end

    def _no_tooling_reask?(previous_event, current_patterns, call_context)
      previous_patterns = _normalized_capability_patterns(previous_event["capability_patterns"])
      return false unless previous_patterns.empty? && current_patterns.empty?
      return false if previous_event.fetch("had_delegated_calls", false) == true
      return false if call_context.fetch(:had_child_calls, false) == true

      true
    end

    def _normalized_capability_patterns(patterns)
      Array(patterns).map(&:to_s).reject(&:empty?).uniq.sort
    end

    def _pattern_memory_normalize_user_correction(value)
      return nil unless value.is_a?(Hash)
      return nil unless value["detected"] == true

      {
        "detected" => true,
        "signal" => value["signal"].to_s,
        "correction_of_call_id" => value["correction_of_call_id"]&.to_s,
        "matched_capability_patterns" => Array(value["matched_capability_patterns"]).map(&:to_s).uniq.sort
      }
    end
  end
end
