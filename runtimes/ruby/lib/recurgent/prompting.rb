# frozen_string_literal: true

class Agent
  # rubocop:disable Metrics/ModuleLength
  module Prompting
    private

    def _tool_schema
      {
        name: "execute_code",
        description: "Provide Ruby code and dependency declarations",
        input_schema: {
          type: "object",
          properties: {
            code: { type: "string", description: "Ruby code to execute" },
            dependencies: {
              type: "array",
              description: "Optional gem dependencies required by the generated code",
              items: {
                type: "object",
                properties: {
                  name: { type: "string", description: "Gem name" },
                  version: { type: "string", description: "Version constraint (optional)" }
                },
                required: ["name"],
                additionalProperties: false
              }
            }
          },
          required: ["code"],
          additionalProperties: false
        }
      }
    end

    def _build_system_prompt(call_context: nil)
      depth = call_context&.fetch(:depth, 0) || 0
      opening = _system_opening_prompt(depth: depth)
      depth_identity = _depth_identity_prompt(depth: depth)
      contract_guidance = _delegation_contract_prompt
      decomposition_nudge = _decomposition_nudge_prompt(depth: depth)
      known_tools = _known_tools_system_prompt
      stance_policy = _stance_policy_prompt(call_context: call_context)
      rules = _system_rules_prompt(depth: depth)
      <<~PROMPT
        #{opening}
        #{depth_identity}
        #{decomposition_nudge}

        You have access to 'context' (a Hash) to store and retrieve data.
        Treat `context` as your working memory.
        Tool registry is available at `context[:tools]` as metadata (authoritative + complete).
        Every dynamic call returns an Outcome object to the caller.
        #{known_tools}
        #{contract_guidance}
        #{stance_policy}
        #{rules}
      PROMPT
    end

    def _system_opening_prompt(depth:)
      case depth
      when 0
        <<~OPENING.chomp
          You are a Tool Builder operating as a Ruby agent called '#{@role}'.
          You create durable, reusable tools by generating Ruby code that will be eval'd in your context.
        OPENING
      when 1
        <<~OPENING.chomp
          You are a Tool operating as a Ruby agent called '#{@role}'.
          You execute delegated work by generating Ruby code that will be eval'd in your context.
        OPENING
      else
        <<~OPENING.chomp
          You are a Worker operating as a Ruby agent called '#{@role}'.
          You execute tasks directly by generating Ruby code that will be eval'd in your context.
        OPENING
      end
    end

    def _depth_identity_prompt(depth:)
      case depth
      when 0
        <<~IDENTITY.chomp
          Purpose: create durable, reusable Tools that compound over time.
          Default posture: Forge/Orchestrate when task has a reusable capability boundary.
        IDENTITY
      when 1
        <<~IDENTITY.chomp
          Purpose: execute delegated contract work efficiently and clearly.
          Default posture: Do/Shape. Forge only when deliverable clearly implies publication of a reusable interface, or parent contract explicitly requests it.
        IDENTITY
      else
        <<~IDENTITY.chomp
          Purpose: execute the assigned task directly and return.
          Default posture: Do. Avoid creating new tools or further delegation unless explicitly required.
        IDENTITY
      end
    end

    def _build_user_prompt(name, args, kwargs, call_context: nil)
      current_context = _prompt_memory_context
      depth = call_context&.fetch(:depth, 0) || 0
      self_check = _user_prompt_self_check(depth: depth)
      examples = _user_prompt_examples(name: name, depth: depth)
      active_contract = _active_contract_user_prompt
      known_tools = _known_tools_prompt
      conversation_history = _conversation_history_user_prompt_block
      recent_patterns = _recent_patterns_prompt(method_name: name, depth: depth)
      interface_overlap = _known_tool_interface_overlap_prompt

      <<~PROMPT
        <invocation>
        <action>
        <method>#{name}</method>
        <args>#{args.inspect}</args>
        <kwargs>#{kwargs.inspect}</kwargs>
        </action>
        <current_depth>#{depth}</current_depth>
        <memory>#{current_context.inspect}</memory>
        </invocation>

        #{conversation_history}

        #{known_tools}
        #{_known_tools_usage_hint}
        #{interface_overlap}
        #{recent_patterns}

        #{active_contract}

        <response_contract>
        - Return a GeneratedProgram payload with `code` and optional `dependencies`.
        - Set `result` to the raw domain value, or use `return` in generated code.
        </response_contract>

        #{examples}

        <self_check>
        #{self_check}
        </self_check>
      PROMPT
    end

    def _decomposition_nudge_prompt(depth:)
      case depth
      when 0
        <<~NUDGE

          Decomposition Nudge:
          - Experienced Tool Builders decompose before acting: separate capability from trigger task.
          - Tool registry metadata is available in full at `context[:tools]` (authoritative).
          - `<known_tools>` below is a non-exhaustive preview for quick scanning.
          - Both `context[:tools]` and `<known_tools>` are metadata, not callable objects.
          - To invoke a known tool, use `tool("tool_name")` (preferred) or `delegate("tool_name", ...)`.
          - Before choosing stance, briefly decompose:
              1. What capability is required? (e.g., HTTP fetch, parsing, summarization)
              2. Is that capability already available in `context[:tools]`?
              3. If missing, what is the most general useful form of the capability?
          - Capability-fit rule:
              treat `capabilities` as optional hints, not strict gates; reason over `purpose`, `methods`, and `deliverable` when tags are missing or ambiguous.
          - Avoid brittle matching:
              do not hard-fail solely because a specific capability tag string is absent.
          - Build-intent rule:
              if the user explicitly asks to build/create/make a tool, treat that as a Forge signal at depth 0 unless blocked by runtime capability limits.
          - Naming nudge:
              prefer names that reflect capability and reuse potential rather than the immediate trigger phrasing.
          - Reuse-first rule:
              if an existing tool already matches capability, reuse or extend it instead of creating a near-duplicate.
        NUDGE
      when 1
        <<~NUDGE

          Decomposition Nudge:
          - You are a Tool executing delegated work: verify whether you can fulfill the task directly with current capabilities.
          - Check `context[:tools]` first before creating anything new.
          - `<known_tools>` is a non-exhaustive preview of the same registry metadata.
          - Registry entries are metadata only; invoke tools via `tool("tool_name")` or explicit `delegate(...)`.
          - If capability is missing, prefer local Shape or typed error; Forge only when the active contract clearly implies a reusable interface.
        NUDGE
      else
        <<~NUDGE

          Decomposition Nudge:
          - You are in worker mode (depth >= 2): prioritize direct execution over decomposition overhead.
          - Use known context/tools only if they immediately reduce work in this call.
        NUDGE
      end
    end

    def _stance_policy_prompt(call_context:)
      depth = call_context&.fetch(:depth, 0) || 0
      case depth
      when 0
        <<~POLICY

          Stance Policy (depth 0):
          - Do: execute directly for this call.
          - Shape: solve now while extracting a local reusable pattern in this flow.
          - Forge: create/refine a durable named Tool contract intended for future reuse.
          - Orchestrate: compose multiple Tools toward a multi-step outcome.

          Shape vs Forge boundary:
          - Shape keeps reuse local to this current call flow.
          - Forge publishes reuse for future invocations via stable method/contract.

          Depth-0 stance selection:
          - If task is a general capability (HTTP fetch, parsing, file I/O, text transformation, data extraction), default to Forge even on first encounter.
          - If user explicitly requests building/creating/making a tool, default to Forge.
          - At depth 0, when in doubt between Do and Forge, choose Forge.
          - Cost model at depth 0: an unused durable tool is cheaper than repeated one-off reimplementation.

          Promotion rules (toward Forge/Orchestrate):
          - For domain-specific tasks: promote when same task shape repeats (rule of 3 or more),
          - and the contract can be made explicit (`purpose`, `deliverable`, `acceptance`, `failure_policy`).
          - For general capabilities at depth 0: promote immediately (first encounter is enough).

          Demotion rules (toward Do/Shape):
          - demote when task is one-off domain-specific work with low reuse potential,
          - or task is quick/reliable and does not represent a reusable capability boundary,
          - or contract boundaries are unclear/speculative.

          Ambiguity handling:
          - at depth 0, when ambiguous between Do and Forge, choose Forge.
          - if ambiguous between Forge and Orchestrate, choose Forge unless orchestration is clearly required.
        POLICY
      when 1
        <<~POLICY

          Stance Policy (depth 1):
          - Default to Do.
          - Use Shape only when a local pattern helps this call.
          - Forge only when active contract/deliverable clearly implies a reusable interface.
          - Orchestrate is not available at this depth.

          Ambiguity handling:
          - when uncertain, choose Do and add a short Ruby comment explaining the conservative choice.
        POLICY
      else
        <<~POLICY

          Stance Policy (depth #{depth}, worker mode):
          - Available stances: Do and Shape.
          - Default to Do.
          - Do not Forge or Orchestrate unless explicitly required by active contract.
          - Keep execution direct, bounded, and return quickly.

          Ambiguity handling:
          - when uncertain, choose Do and add a short Ruby comment.
        POLICY
      end
    end

    def _system_rules_prompt(depth:)
      output_contract = _output_format_contract_prompt
      capability_boundaries = _capability_boundaries_prompt
      design_quality = _design_quality_prompt(depth: depth)
      <<~RULES
        Rule Priority Order (highest first):
        1. Output Format Contract (MUST)
        2. Capability and Side-Effect Boundaries (MUST)
        3. Tool Design Quality and Delegation Discipline (SHOULD, unless it conflicts with 1 or 2)

        #{output_contract}
        #{capability_boundaries}
        #{design_quality}
      RULES
    end

    def _output_format_contract_prompt
      <<~RULES
        Output Format Contract:
        - Always respond with valid GeneratedProgram payload via the execute_code tool.
        - The payload MUST include `code` and MAY include `dependencies`.
        - Set `result` or use `return` to produce the raw domain value (runtime wraps it in Outcome).
        - Avoid `redo` unless in a clearly bounded loop; unbounded `redo` can cause non-terminating execution.
      RULES
    end

    def _capability_boundaries_prompt
      <<~RULES
        Capability and Side-Effect Boundaries:
        - Side-effect integrity first: do NOT claim timers/reminders/notifications/background jobs are set unless code actually schedules them.
        - Writing to context is internal memory only, not an external side effect.
        - Be truthful and capability-accurate; never claim an action occurred unless this code actually performed it.
        - You can access and modify context to store persistent data.
        - State-key continuity rule:
            1. If context already has a key for the same semantic state, reuse that key.
            2. If no scalar accumulator key exists yet, default to `context[:value]`.
            3. Do not create parallel scalar aliases (for example `:memory`, `:accumulator`, `:calculator_value`) for the same state unless explicitly required.
            4. Setter/readback coherence: if caller sets `obj.foo = x`, prefer `context[:foo]` for that semantic state.
        - `context[:tools]` is a Hash keyed by tool name; each value is tool metadata (purpose, methods, capabilities, stats).
        - For registry checks, prefer `context[:tools].key?("tool_name")` or `context[:tools].each do |tool_name, metadata| ... end`.
        - `context[:conversation_history]` is available as a structured Array of prior call records; prefer direct Ruby filtering/querying when needed.
        - Conversation-history records are additive; treat optional fields defensively (`record[:field] || record["field"]`).
        - Source-followup rule: if user asks for source/provenance/how data was obtained, query `context[:conversation_history]` first and answer from prior `outcome_summary` source refs when present.
        - For source follow-ups, prefer the most recent relevant successful record and include concrete refs (`primary_uri`, `retrieval_mode`, `source_count`, `timestamp` when available).
        - Never infer or fabricate provenance if history refs are missing; return explicit unknown/missing-source response instead.
        - Outcome constructors available: Agent::Outcome.ok(...), Agent::Outcome.error(...), Agent::Outcome.call(value=nil, ...).
        - Prefer Agent::Outcome.ok/error as canonical forms; Agent::Outcome.call is a tolerant success alias.
        - Outcome API idioms: use `outcome.ok?` / `outcome.error?` for branching, then `outcome.value` or `outcome.error_message`. (`success?`/`failure?` are tolerated aliases.)
        - For tool composition, preserve contract shapes: pass only fields expected by the downstream method (for example, RSS parser gets raw feed string, not fetch envelope Hash).
        - When consuming tool output hashes, handle both symbol and string keys unless you explicitly normalized keys.
        - For HTTP fetch operations, prefer https endpoints and handle 3xx redirects with a bounded hop count before failing.
        - External-data success invariant: if code fetches/parses remote data and returns success, include provenance envelope.
        - Provenance envelope shape (tolerant key types): `provenance: { sources: [{ uri:, fetched_at:, retrieval_tool:, retrieval_mode: ("live"|"cached"|"fixture") }] }`.
        - You may require Ruby standard library (net/http, json, date, socket, etc.) but NOT external gems.
        - If your design needs non-stdlib gems, declare each one in `dependencies`; keep declarations minimal and non-speculative.
        - delegation does NOT grant new capabilities; child tools inherit the same runtime/tooling limits.
        - Do NOT delegate recursively to bypass unavailable capabilities.
        - If blocked by unavailable capability, return a typed non-retriable error outcome instead of fake success.
        - If output is structurally valid but not useful for caller intent, return `Agent::Outcome.error(error_type: "low_utility", ...)` instead of `Outcome.ok` with placeholder status.
        - For user requests that explicitly ask for a list/items/results, guidance-only prose without concrete items is `low_utility`, not success.
        - If request crosses this Tool's boundary, return `Agent::Outcome.error(error_type: "wrong_tool_boundary", ...)` with metadata such as `boundary_axes`, `observed_task_shape`, and optional `suggested_split`.
        - Compare active `intent_signature` with Tool purpose/capabilities; if mismatched, prefer `wrong_tool_boundary` over low-quality success.
        - If usefulness must be enforced inline, encode it as machine-checkable `deliverable` constraints (for example `min_items`) rather than relying on status strings.
        - For dependency-backed execution, results and context must stay JSON-serializable.
        - Be context-capacity aware: if memory grows large, prefer summarizing/pruning stale data over unbounded accumulation.
      RULES
    end

    def _design_quality_prompt(depth:)
      shared = <<~RULES
        Tool Design Quality and Delegation Discipline:
        - Infer what methods and behaviors are natural for role '#{@role}'.
        - Method names should be intuitive verbs or queries a caller would expect for this role.
        - Write clean, focused code that fulfills the active intent/contract.
        - Initialize local accumulators before appending (for example `lines = []`, `response = +""`) before calling `<<`/`push`.
        - Parameterize inputs only when it improves clarity for the current implementation.
        - Do NOT over-generalize into frameworks or speculative abstractions.
        - If reuse is unlikely or semantics are unclear, keep scope narrow and explicit.
        - Do NOT mutate Agent/Tool objects with metaprogramming (for example `define_singleton_method`); express behavior through normal generated methods and tool/delegate invocation paths.
      RULES

      depth_rules = case depth
                    when 0
                      <<~RULES
                        - Prefer reusable, parameterized interfaces.
                        - Generalize one step above the immediate task (task-adjacent generality).
                        - Parameterize obvious inputs (url, query, filepath, etc.); e.g., prefer fetch_url(url) over fetch_specific_article().
                        - At depth 0, for general capabilities (HTTP fetch/parsing/file I/O/text transform), prefer Forge even if direct code is short.
                        - Tool registry is authoritative at `context[:tools]`. Query it directly to find capability-fit candidates.
                        - Reuse by materializing with `tool("name")` (or explicit `delegate(...)`), not by calling `context[:tools]` entries as executable objects.
                        - When delegating, strongly prefer an explicit contract:
                            tool = delegate(
                              "translator",
                              purpose: "translate user text accurately",
                              deliverable: { type: "string" },
                              acceptance: [{ assert: "output is translated text in target language" }],
                              failure_policy: { on_error: "return_error" }
                            )
                            translation = tool.translate("hello world")
                            if translation.ok?
                              result = translation.value
                            else
                              result = "translator failed: \#{translation.error_type}"
                            end
                        - Delegated outcomes expose: ok?, error?, value, value_or(default), error_type, error_message, retriable.
                      RULES
                    when 1
                      <<~RULES
                        - Depth 1 is execution-first: prefer direct implementation and local shaping.
                        - Do NOT delegate if the task is a simple computation/string operation or can be done in fewer than 10 lines.
                        - Forge only when active contract/deliverable clearly implies a reusable interface.
                        - If blocked by unavailable capability, return typed error outcome instead of pushing delegation deeper.
                      RULES
                    else
                      <<~RULES
                        - Worker mode: do not create new tools or delegate further unless explicitly required.
                        - Keep code short, direct, and narrowly scoped to the current call.
                      RULES
                    end

      "#{shared}#{depth_rules}"
    end

    def _user_prompt_self_check(depth:)
      base = <<~CHECK.chomp
        - Did my code actually perform every action I describe in `result`?
        - Am I returning real computed data, not placeholder/example data?
        - If capability blocked execution, did I return Agent::Outcome.error with typed metadata?
        - If a fetch/parse/external operation failed, did I avoid returning a plain success string that only says it failed?
        - If I fetched/parsing succeeded technically but produced empty/junk output, did I return `low_utility` instead of `Outcome.ok`?
        - If I returned success for external data, did I include provenance with sources + retrieval_mode?
        - If user asked for list/items/results, did I return concrete items instead of guidance-only prose?
        - If this is a source/provenance follow-up, did I cite concrete source refs from history (`primary_uri`, `retrieval_mode`, `source_count`) instead of generic prose?
        - Does my stance choice fit current depth policy from the system prompt?
      CHECK

      depth_checks = case depth
                     when 0
                       <<~CHECK.chomp
                         - At depth 0, if this is a reusable general capability, did I choose Forge over one-off inline code?
                         - Did I decompose capability from trigger task and check for reusable existing tools first?
                         - If forging, does the interface maximize future reuse instead of solving only this trigger phrasing?
                         - If I delegated, was delegation necessary, or could I do this directly in fewer than 10 lines?
                       CHECK
                     when 1
                       <<~CHECK.chomp
                         - At depth 1, did I default to direct execution (Do) unless local Shape was clearly useful?
                         - Did I avoid delegation when direct code could solve this quickly?
                         - If I forged, did the active contract/deliverable clearly require a reusable interface?
                       CHECK
                     else
                       <<~CHECK.chomp
                         - In worker mode, did I keep execution direct and avoid creating new tools/delegations?
                       CHECK
                     end

      "#{base}\n#{depth_checks}"
    end

    def _known_tools_system_prompt
      <<~TOOLS
        Tool Registry Snapshot:
        #{_known_tools_prompt.rstrip}
        #{_known_tools_usage_hint.rstrip}
      TOOLS
    end

    def _prompt_memory_context
      snapshot = @context.dup
      snapshot.delete(:tools)
      snapshot.delete("tools")
      tools = _known_tools_snapshot
      snapshot[:tools] = { count: tools.length } if tools.is_a?(Hash)
      history = _conversation_history_records
      snapshot[:conversation_history] = { count: history.length }
      snapshot
    end

    def _conversation_history_user_prompt_block
      history = _conversation_history_records
      <<~HISTORY
        <conversation_history>
        <record_count>#{history.length}</record_count>
        <access_hint>History contents are available in context[:conversation_history]. Inspect via generated Ruby code when needed; prompt does not preload records.</access_hint>
        <record_schema>Each record includes: call_id, timestamp, speaker, method_name, args, kwargs, outcome_summary.</record_schema>
        <source_refs_hint>When present, outcome_summary may include compact source refs: source_count, primary_uri, retrieval_mode.</source_refs_hint>
        <query_hint>Prefer canonical fields (`record[:args]`, `record[:method_name]`, `record[:outcome_summary]`); do not rely on ad hoc keys.</query_hint>
        <source_query_protocol>
        - If current ask is about source/provenance/how data was obtained:
          1) filter recent records with source refs in `outcome_summary`,
          2) prefer the most recent relevant successful record,
          3) answer with concrete refs (`primary_uri`, `retrieval_mode`, `source_count`),
          4) if refs are missing, state unknown rather than inferring.
        </source_query_protocol>
        </conversation_history>
      HISTORY
    end

    def _known_tools_prompt
      tools = _known_tools_snapshot
      return "<known_tools></known_tools>\n" unless tools.is_a?(Hash) && !tools.empty?

      ranked_tools = _rank_known_tools_for_prompt(tools)
      lines = ranked_tools.first(Agent::KNOWN_TOOLS_PROMPT_LIMIT).map do |name, metadata|
        purpose = _extract_tool_purpose(metadata)
        methods = _extract_tool_methods(metadata)
        capabilities = _extract_tool_capabilities(metadata)
        intent_signatures = _extract_tool_intent_signatures(metadata)
        lifecycle_state = _extract_tool_lifecycle_state(metadata)
        policy_version = _extract_tool_policy_version(metadata)
        reliability_summary = _extract_tool_reliability_summary(metadata)
        suffix = +""
        suffix << "\n  methods: [#{methods.join(", ")}]" unless methods.empty?
        suffix << "\n  capabilities: [#{capabilities.join(", ")}]" unless capabilities.empty?
        suffix << "\n  intent_signatures: [#{intent_signatures.join(", ")}]" unless intent_signatures.empty?
        unless lifecycle_state.nil?
          lifecycle_line = "lifecycle: #{lifecycle_state}"
          lifecycle_line += " (policy: #{policy_version})" unless policy_version.nil?
          suffix << "\n  #{lifecycle_line}"
        end
        suffix << "\n  reliability: #{reliability_summary}" unless reliability_summary.nil?
        suffix << "\n  caution: #{_extract_tool_degraded_caution(metadata)}" if lifecycle_state == "degraded"
        "- #{name}: #{purpose}#{suffix}"
      end

      <<~TOOLS
        <known_tools>
        #{lines.join("\n")}
        </known_tools>
      TOOLS
    end

    def _known_tools_usage_hint
      <<~HINT
        <known_tools_usage>
        - Tool registry is available in full at `context[:tools]` (authoritative, complete metadata).
        - `context[:tools]` shape: `{ "tool_name" => { purpose:, methods:, capabilities:, ... } }`.
        - `<known_tools>` is a non-exhaustive preview for quick scanning.
        - Match by capability-fit: use `capabilities` when present, and infer from `purpose` + `methods` + `deliverable` when tags are missing.
        - Query `context[:tools]` directly to find best-fit candidates, then materialize the chosen tool.
        - Do NOT call values from `context[:tools]` directly; they are metadata, not executable objects.
        - To reuse a known tool, materialize it with `tool("tool_name")` (preferred) or `delegate("tool_name", ...)`.
        </known_tools_usage>
      HINT
    end

    def _extract_tool_purpose(metadata)
      return "purpose unavailable" unless metadata.is_a?(Hash)

      metadata[:purpose] || metadata["purpose"] || "purpose unavailable"
    end

    def _extract_tool_methods(metadata)
      return [] unless metadata.is_a?(Hash)

      Array(metadata[:methods] || metadata["methods"]).map { |name| name.to_s.strip }.reject(&:empty?).uniq
    end

    def _extract_tool_capabilities(metadata)
      return [] unless metadata.is_a?(Hash)

      explicit = _explicit_tool_capabilities(metadata)
      return explicit unless explicit.empty?

      _heuristic_tool_capabilities(_heuristic_tool_capability_source_text(metadata))
    end

    def _extract_tool_intent_signatures(metadata)
      return [] unless metadata.is_a?(Hash)

      signatures = Array(metadata[:intent_signatures] || metadata["intent_signatures"])
      signatures << metadata[:intent_signature] if metadata.key?(:intent_signature)
      signatures << metadata["intent_signature"] if metadata.key?("intent_signature")
      signatures
        .map { |value| value.to_s.strip }
        .reject(&:empty?)
        .uniq
    end

    def _extract_tool_lifecycle_state(metadata)
      value = _known_tool_lifecycle_state(metadata)
      return nil if value.nil? || value.to_s.strip.empty?

      value
    end

    def _extract_tool_policy_version(metadata)
      return nil unless metadata.is_a?(Hash)

      explicit = metadata[:promotion_policy_version] || metadata["promotion_policy_version"]
      explicit = explicit.to_s.strip
      return explicit unless explicit.empty?

      scorecards = metadata[:version_scorecards] || metadata["version_scorecards"]
      return nil unless scorecards.is_a?(Hash)

      scorecards.values.each do |entry|
        next unless entry.is_a?(Hash)

        version = entry[:policy_version] || entry["policy_version"]
        normalized = version.to_s.strip
        return normalized unless normalized.empty?
      end

      nil
    end

    def _extract_tool_reliability_summary(metadata)
      return nil unless metadata.is_a?(Hash)

      scorecards = metadata[:version_scorecards] || metadata["version_scorecards"]
      if scorecards.is_a?(Hash) && !scorecards.empty?
        totals = scorecards.values.each_with_object(
          calls: 0,
          successes: 0,
          failures: 0,
          wrong_boundary: 0,
          retries_exhausted: 0
        ) do |entry, acc|
          next unless entry.is_a?(Hash)

          acc[:calls] += (entry[:calls] || entry["calls"]).to_i
          acc[:successes] += (entry[:successes] || entry["successes"]).to_i
          acc[:failures] += (entry[:failures] || entry["failures"]).to_i
          acc[:wrong_boundary] += (entry[:wrong_boundary_count] || entry["wrong_boundary_count"]).to_i
          guardrail = (entry[:guardrail_retry_exhausted_count] || entry["guardrail_retry_exhausted_count"]).to_i
          outcome = (entry[:outcome_retry_exhausted_count] || entry["outcome_retry_exhausted_count"]).to_i
          acc[:retries_exhausted] += guardrail + outcome
        end
        return nil if totals[:calls].zero?

        success_rate = totals[:successes].to_f.fdiv(totals[:calls]).round(2)
        return [
          "calls=#{totals[:calls]}",
          "success_rate=#{success_rate}",
          "wrong_boundary=#{totals[:wrong_boundary]}",
          "retries_exhausted=#{totals[:retries_exhausted]}"
        ].join(", ")
      end

      success_count = (metadata[:success_count] || metadata["success_count"]).to_i
      failure_count = (metadata[:failure_count] || metadata["failure_count"]).to_i
      calls = success_count + failure_count
      return nil if calls.zero?

      "calls=#{calls}, success_rate=#{(success_count.to_f.fdiv(calls)).round(2)}"
    end

    def _extract_tool_degraded_caution(metadata)
      decision = nil
      if metadata.is_a?(Hash)
        decision = metadata[:lifecycle_decision] || metadata["lifecycle_decision"]
        if decision.nil?
          scorecards = metadata[:version_scorecards] || metadata["version_scorecards"]
          if scorecards.is_a?(Hash)
            scorecards.values.each do |entry|
              next unless entry.is_a?(Hash)

              candidate = entry[:last_decision] || entry["last_decision"]
              next if candidate.nil? || candidate.to_s.strip.empty?

              decision = candidate
              break
            end
          end
        end
      end

      base = "degraded by promotion policy"
      decision.nil? ? base : "#{base} (last_decision=#{decision})"
    end

    def _known_tool_interface_overlap_prompt
      overlaps = _known_tool_method_overlaps
      return "" if overlaps.empty?

      lines = overlaps.map do |entry|
        methods = entry[:methods].join(", ")
        "- #{entry[:name]} has multiple methods for similar capability: [#{methods}]"
      end

      <<~PROMPT
        <interface_overlap_observations>
        #{lines.join("\n")}
        - Consider consolidating to one canonical method when behavior overlaps.
        </interface_overlap_observations>
      PROMPT
    end

    def _known_tool_method_overlaps
      tools = _known_tools_snapshot
      return [] unless tools.is_a?(Hash)

      tools.filter_map do |name, metadata|
        methods = _extract_tool_methods(metadata)
        next if methods.length < 2

        { name: name.to_s, methods: methods.sort }
      end.first(Agent::KNOWN_TOOLS_PROMPT_LIMIT)
    end

    def _known_tools_snapshot
      persisted_tools = _toolstore_load_registry_tools
      memory_tools = @context[:tools]

      snapshot = _merge_known_tools_for_prompt(persisted_tools, memory_tools)
      @context[:tools] = snapshot if snapshot.is_a?(Hash) && !snapshot.empty?
      snapshot
    end

    def _merge_known_tools_for_prompt(persisted_tools, memory_tools)
      persisted = _normalized_known_tools_hash(persisted_tools)
      memory = _normalized_known_tools_hash(memory_tools)
      return {} if persisted.empty? && memory.empty?

      _merge_known_tool_indexes(persisted, memory)
    end

    def _normalized_known_tools_hash(tools)
      return {} unless tools.is_a?(Hash)

      tools
    end

    def _merge_known_tool_indexes(persisted, memory)
      _known_tool_names(persisted, memory).each_with_object({}) do |name, merged|
        merged[name] = _merge_known_tool_metadata_for_prompt(
          _known_tool_metadata_for_name(persisted, name),
          _known_tool_metadata_for_name(memory, name)
        )
      end
    end

    def _known_tool_names(persisted, memory)
      (persisted.keys + memory.keys).map(&:to_s).uniq
    end

    def _known_tool_metadata_for_name(tools, name)
      tools[name] || tools[name.to_sym]
    end

    def _merge_known_tool_metadata_for_prompt(persisted_metadata, memory_metadata)
      persisted = persisted_metadata.is_a?(Hash) ? _normalize_loaded_tool_metadata(persisted_metadata) : {}
      memory = memory_metadata.is_a?(Hash) ? _normalize_loaded_tool_metadata(memory_metadata) : {}

      merged = persisted.merge(memory)
      merged[:methods] = _merge_known_tool_string_lists(persisted, memory, :methods)
      merged[:aliases] = _merge_known_tool_string_lists(persisted, memory, :aliases)
      merged[:intent_signatures] = _merge_known_tool_intent_signatures(persisted, memory)
      merged[:intent_signature] = merged[:intent_signatures].last unless merged[:intent_signatures].empty?
      merged[:capabilities] = _extract_tool_capabilities(merged)
      merged
    end

    def _explicit_tool_capabilities(metadata)
      Array(metadata[:capabilities] || metadata["capabilities"])
        .map { |tag| tag.to_s.strip.downcase }
        .reject(&:empty?)
        .uniq
    end

    def _heuristic_tool_capability_source_text(metadata)
      parts = [
        _extract_tool_purpose(metadata),
        _extract_tool_methods(metadata).join(" ")
      ]
      deliverable = metadata[:deliverable] || metadata["deliverable"]
      parts << deliverable.inspect if deliverable
      parts.join(" ").downcase
    end

    def _heuristic_tool_capabilities(text)
      capability_rules = [
        ["http_fetch", /\b(http|https|url|fetch|net::http)\b/],
        ["rss_parse", /\brss\b/],
        ["html_extract", /\b(html|scrape|extract|parse)\b/],
        ["news_headline_extract", /\b(news|headline)\b/],
        ["movie_listings", /\b(movie|theater|showtime|listing)\b/],
        ["json_parse", /\bjson\b/],
        ["text_summarization", /\b(summary|summarize|synthesis)\b/]
      ]

      capability_rules
        .select { |(_, pattern)| text.match?(pattern) }
        .map(&:first)
    end

    def _merge_known_tool_string_lists(persisted, memory, key)
      left = Array(persisted[key] || persisted[key.to_s]).map { |value| value.to_s.strip }.reject(&:empty?)
      right = Array(memory[key] || memory[key.to_s]).map { |value| value.to_s.strip }.reject(&:empty?)
      (left + right).uniq
    end

    def _merge_known_tool_intent_signatures(persisted, memory)
      (_extract_tool_intent_signatures(persisted) + _extract_tool_intent_signatures(memory)).uniq
    end

    def _extract_tool_aliases(metadata)
      return [] unless metadata.is_a?(Hash)

      Array(metadata[:aliases] || metadata["aliases"]).map { |name| name.to_s.strip }.reject(&:empty?).uniq
    end

    # rubocop:disable Metrics/MethodLength
    def _user_prompt_examples(name:, depth:)
      return "" unless _emit_user_prompt_examples?

      case depth
      when 0
        <<~EXAMPLES
          <examples>
          <pattern kind="stateful_operation">
          ```ruby
          context[:value] = context.fetch(:value, 0) + 1
          result = context[:value]
          ```
          </pattern>

          <pattern kind="read_only_query">
          ```ruby
          result = context.fetch(:value, 0)
          ```
          </pattern>

          <pattern kind="capability_limited_error">
          ```ruby
          result = Agent::Outcome.error(
            error_type: "unsupported_capability",
            error_message: "Required capability is unavailable in this runtime.",
            retriable: false,
            tool_role: @role,
            method_name: "#{name}"
          )
          ```
          </pattern>

          <pattern kind="delegation_with_contract">
          ```ruby
          tool = delegate(
            "analyst",
            purpose: "analyze context data and return concise findings",
            deliverable: { type: "object", required: ["summary"] },
            acceptance: [{ assert: "summary is present" }],
            failure_policy: { on_error: "return_error" }
          )
          analysis = tool.summarize(context[:data])
          result = analysis.ok? ? analysis.value : "analysis failed: \#{analysis.error_type}"
          ```
          </pattern>

          <pattern kind="forge_reusable_capability">
          ```ruby
          # Depth 0: general capability recognized as reusable, so Forge.
          web_fetcher = delegate(
            "web_fetcher",
            purpose: "fetch and parse content from urls",
            deliverable: { type: "object", required: ["status", "body"] },
            acceptance: [{ assert: "status and body are present" }],
            failure_policy: { on_error: "return_error" }
          )
          fetched = web_fetcher.fetch_url("https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en")
          result = fetched.ok? ? fetched.value : Agent::Outcome.error(
            error_type: fetched.error_type,
            error_message: fetched.error_message,
            retriable: fetched.retriable,
            tool_role: @role,
            method_name: "#{name}"
          )
          ```
          </pattern>

          <pattern kind="external_data_success_with_provenance">
          ```ruby
          fetcher = tool("web_fetcher")
          fetched = fetcher.fetch_url("https://example.com/feed")
          if fetched.ok?
            payload = fetched.value
            stories = payload[:items] || payload["items"] || []
            result = Agent::Outcome.ok(
              data: stories,
              provenance: {
                sources: [
                  {
                    uri: "https://example.com/feed",
                    fetched_at: Time.now.utc.iso8601,
                    retrieval_tool: "web_fetcher",
                    retrieval_mode: "live"
                  }
                ]
              }
            )
          else
            result = Agent::Outcome.error(
              error_type: fetched.error_type,
              error_message: fetched.error_message,
              retriable: fetched.retriable,
              tool_role: @role,
              method_name: "#{name}"
            )
          end
          ```
          </pattern>

          <pattern kind="reuse_known_tool">
          ```ruby
          # Query full registry metadata from context[:tools], then materialize the best-fit tool.
          # `capabilities` are optional hints; fall back to purpose/method reasoning when tags are absent.
          registry = context[:tools] || {}
          candidate_name, _candidate_meta = registry.max_by do |_tool_name, metadata|
            caps = Array(metadata[:capabilities] || metadata["capabilities"]).map { |tag| tag.to_s.downcase }
            purpose = (metadata[:purpose] || metadata["purpose"]).to_s.downcase
            methods = Array(metadata[:methods] || metadata["methods"]).map { |m| m.to_s.downcase }
            deliverable = (metadata[:deliverable] || metadata["deliverable"]).inspect.downcase
            score = 0
            score += 3 if caps.include?("http_fetch")
            score += 2 if methods.any? { |m| m.include?("fetch") || m.include?("url") }
            score += 1 if purpose.match?(/\b(fetch|http|https|url)\b/)
            score += 1 if deliverable.match?(/\bbody\b/)
            score
          end
          chosen_tool = candidate_name || "web_fetcher"
          web_fetcher = tool(chosen_tool)
          fetched = web_fetcher.fetch_url("https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en")
          if fetched.ok?
            payload = fetched.value
            result = payload[:content] || payload["content"] || payload
          else
            result = Agent::Outcome.error(
              error_type: fetched.error_type,
              error_message: fetched.error_message,
              retriable: fetched.retriable,
              tool_role: @role,
              method_name: "#{name}"
            )
          end
          ```
          </pattern>
          </examples>
        EXAMPLES
      when 1
        <<~EXAMPLES
          <examples>
          <pattern kind="direct_execution_default">
          ```ruby
          # Depth 1 default: do the work directly unless contract demands reusable publication.
          value = kwargs.fetch(:value, args.first)
          result = value.to_s.strip
          ```
          </pattern>

          <pattern kind="local_shape_pattern">
          ```ruby
          # Local shape: extract a small helper pattern for this call only.
          normalize = ->(text) { text.to_s.downcase.strip }
          result = normalize.call(kwargs.fetch(:query, args.first))
          ```
          </pattern>

          <pattern kind="capability_limited_error">
          ```ruby
          result = Agent::Outcome.error(
            error_type: "unsupported_capability",
            error_message: "Required capability is unavailable in this runtime.",
            retriable: false,
            tool_role: @role,
            method_name: "#{name}"
          )
          ```
          </pattern>
          </examples>
        EXAMPLES
      else
        <<~EXAMPLES
          <examples>
          <pattern kind="worker_direct_execution">
          ```ruby
          # Worker mode: execute directly and return.
          result = args.first
          ```
          </pattern>

          <pattern kind="capability_limited_error">
          ```ruby
          result = Agent::Outcome.error(
            error_type: "unsupported_capability",
            error_message: "Required capability is unavailable in this runtime.",
            retriable: false,
            tool_role: @role,
            method_name: "#{name}"
          )
          ```
          </pattern>
          </examples>
        EXAMPLES
      end
    end
    # rubocop:enable Metrics/MethodLength

    def _active_contract_user_prompt
      return "" unless @delegation_contract

      intent_signature = @delegation_contract[:intent_signature]
      intent_line = intent_signature.nil? ? "" : "\n<intent_signature>#{intent_signature.inspect}</intent_signature>"
      <<~CONTRACT
        <active_contract>
        <purpose>#{@delegation_contract[:purpose].inspect}</purpose>
        <deliverable>#{@delegation_contract[:deliverable].inspect}</deliverable>
        <acceptance>#{@delegation_contract[:acceptance].inspect}</acceptance>
        <failure_policy>#{@delegation_contract[:failure_policy].inspect}</failure_policy>
        #{intent_line}
        </active_contract>
      CONTRACT
    end

    def _emit_user_prompt_examples?
      return false if @user_prompt_examples_emitted

      @user_prompt_examples_emitted = true
      true
    end

    def _delegation_contract_prompt
      return _no_contract_prompt unless @delegation_contract

      intent_signature = @delegation_contract[:intent_signature]
      intent_line = intent_signature.nil? ? "" : "\n- intent_signature: #{intent_signature.inspect}"
      <<~PROMPT

        Tool Builder Delegation Contract:
        - purpose: #{@delegation_contract[:purpose].inspect}
        - deliverable: #{@delegation_contract[:deliverable].inspect}
        - acceptance: #{@delegation_contract[:acceptance].inspect}
        - failure_policy: #{@delegation_contract[:failure_policy].inspect}
        #{intent_line}
        Treat this as the active contract for this tool call.
      PROMPT
    end

    def _no_contract_prompt
      <<~PROMPT

        Operating Mode:
        - No delegation contract is active.
        - You are defining this role interface from scratch.
        - Choose method behavior that feels natural and unsurprising to the caller.
      PROMPT
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
