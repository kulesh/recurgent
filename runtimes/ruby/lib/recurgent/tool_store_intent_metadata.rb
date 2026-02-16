# frozen_string_literal: true

class Agent
  # Agent::ToolStoreIntentMetadata — intent-signature merge helpers for tool registry entries.
  module ToolStoreIntentMetadata
    private

    def _toolstore_apply_intent_metadata!(merged, existing, incoming)
      signatures = (_toolstore_intent_signatures(existing) + _toolstore_intent_signatures(incoming)).uniq.last(6)
      merged[:intent_signatures] = signatures
      merged[:intent_signature] = signatures.last unless signatures.empty?
    end

    def _toolstore_intent_signatures(metadata)
      return [] unless metadata.is_a?(Hash)

      signatures = Array(metadata[:intent_signatures] || metadata["intent_signatures"])
      signatures << metadata[:intent_signature] if metadata.key?(:intent_signature)
      signatures << metadata["intent_signature"] if metadata.key?("intent_signature")
      signatures.map { |value| value.to_s.strip }.reject(&:empty?).uniq
    end
  end
end
