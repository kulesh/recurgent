# frozen_string_literal: true

class Agent
  # Agent::ProposalStore — persistence for evolution proposals generated from runtime evidence.
  module ProposalStore
    private

    def _proposal_create(proposal_type:, target:, proposed_diff_summary:, evidence_refs:, metadata:)
      normalized_type = proposal_type.to_s.strip
      raise ArgumentError, "proposal_type must be provided" if normalized_type.empty?

      proposals = _proposal_load_all
      timestamp = _proposal_timestamp
      proposal = {
        id: _proposal_id,
        proposal_type: normalized_type,
        target: _json_safe(target),
        evidence_refs: Array(evidence_refs).map(&:to_s).reject(&:empty?),
        proposed_diff_summary: proposed_diff_summary.to_s,
        metadata: _json_safe(metadata || {}),
        status: "proposed",
        created_at: timestamp,
        updated_at: timestamp,
        author_context: {
          role: @role,
          model: @model_name,
          trace_id: @trace_id
        }
      }
      proposals << proposal
      _proposal_write_all(proposals)
      proposal
    end

    def _proposal_list(status: nil, limit: nil)
      proposals = _proposal_load_all
      normalized_status = status.to_s.strip
      unless normalized_status.empty?
        proposals = proposals.select { |proposal| proposal["status"].to_s == normalized_status }
      end
      return proposals unless limit

      proposals.last(limit.to_i)
    end

    def _proposal_find(proposal_id)
      id = proposal_id.to_s
      return nil if id.empty?

      _proposal_load_all.find { |proposal| proposal["id"].to_s == id }
    end

    def _proposal_update_status(proposal_id:, status:, actor:, note: nil)
      id = proposal_id.to_s
      return nil if id.empty?

      proposals = _proposal_load_all
      index = proposals.index { |proposal| proposal["id"].to_s == id }
      return nil unless index

      proposal = proposals[index]
      timestamp = _proposal_timestamp
      proposal["status"] = status.to_s
      proposal["updated_at"] = timestamp
      proposal["last_action"] = {
        "status" => status.to_s,
        "actor" => actor.to_s,
        "at" => timestamp
      }
      proposal["last_action"]["note"] = note.to_s unless note.nil?
      proposals[index] = proposal
      _proposal_write_all(proposals)
      proposal
    end

    def _proposal_load_all
      path = _toolstore_proposals_path
      return [] unless File.exist?(path)

      payload = JSON.parse(File.read(path))
      return [] unless payload.is_a?(Hash)

      proposals = payload["proposals"]
      return [] unless proposals.is_a?(Array)

      proposals
    rescue JSON::ParserError => e
      _proposal_quarantine_corrupt_file!(path, e)
      []
    rescue StandardError => e
      warn "[AGENT PROPOSALS #{@role}] failed to load proposals: #{e.class}: #{e.message}" if @debug
      []
    end

    def _proposal_write_all(proposals)
      path = _toolstore_proposals_path
      FileUtils.mkdir_p(File.dirname(path))
      payload = {
        schema_version: Agent::TOOLSTORE_SCHEMA_VERSION,
        proposals: _json_safe(proposals)
      }

      temp_path = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.write(temp_path, JSON.generate(payload))
      File.rename(temp_path, path)
    ensure
      File.delete(temp_path) if defined?(temp_path) && temp_path && File.exist?(temp_path)
    end

    def _proposal_quarantine_corrupt_file!(path, error)
      return unless File.exist?(path)

      quarantined_path = "#{path}.corrupt-#{Time.now.utc.strftime("%Y%m%dT%H%M%S")}"
      FileUtils.mv(path, quarantined_path)
      if @debug
        warn(
          "[AGENT PROPOSALS #{@role}] quarantined corrupt proposals: #{File.basename(quarantined_path)} (#{error.class})"
        )
      end
    rescue StandardError => e
      warn "[AGENT PROPOSALS #{@role}] failed to quarantine proposals: #{e.class}: #{e.message}" if @debug
    end

    def _proposal_timestamp
      Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
    end

    def _proposal_id
      "prop-#{SecureRandom.hex(8)}"
    end
  end
end
