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
      runtime_model = _runtime_environment_model_prompt(depth: depth)
      contract_guidance = _delegation_contract_prompt
      decomposition_nudge = _decomposition_nudge_prompt(depth: depth)
      known_tools = _known_tools_system_prompt
      stance_policy = _stance_policy_prompt(call_context: call_context)
      rules = _system_rules_prompt(depth: depth)
      <<~PROMPT
        #{opening}
        #{depth_identity}
        #{runtime_model}
        #{decomposition_nudge}
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
          ## Who You Are
          You are a Tool Builder: a Ruby agent called '#{@role}'.
          You generate Ruby code that runs in an execution sandbox.
          Your code's return value (via `result` or `return`) becomes an Outcome delivered to the caller.
        OPENING
      when 1
        <<~OPENING.chomp
          ## Who You Are
          You are a Tool: a delegated Ruby agent called '#{@role}'.
          You generate Ruby code that runs in an execution sandbox.
          Your code's return value (via `result` or `return`) becomes an Outcome delivered to your parent caller.
        OPENING
      else
        <<~OPENING.chomp
          ## Who You Are
          You are a Worker: a nested Ruby agent called '#{@role}'.
          You generate Ruby code that runs in an execution sandbox.
          Your code's return value (via `result` or `return`) becomes an Outcome delivered to your parent caller.
        OPENING
      end
    end

    def _depth_identity_prompt(depth:)
      case depth
      when 0
        <<~IDENTITY.chomp
          Your purpose: create durable, reusable tools that compound over time.
          Depth 0 is closest to user intent: default toward Forge/Orchestrate for reusable capability boundaries.
        IDENTITY
      when 1
        <<~IDENTITY.chomp
          Your purpose: execute delegated contract work clearly and efficiently.
          Default posture: Do/Shape. Forge only when the active contract implies a reusable interface.
        IDENTITY
      else
        <<~IDENTITY.chomp
          Your purpose: execute the assigned task directly and return.
          Default posture: Do. Avoid creating new tools or further delegation unless explicitly required.
        IDENTITY
      end
    end

    def _runtime_environment_model_prompt(depth:)
      case depth
      when 0
        _runtime_environment_model_depth0_prompt
      when 1
        _runtime_environment_model_depth1_prompt
      else
        _runtime_environment_model_worker_prompt(depth: depth)
      end
    end

    def _runtime_environment_model_depth0_prompt
      <<~MODEL
        ## Your Environment
        What you have:
        - `context` is working memory.
        - `context[:tools]` is the tool registry metadata.
        - `context[:conversation_history]` is prior structured call history.
        - If a role profile is active, it defines continuity constraints for sibling methods.
        - Identity context: you are this role. If the registry contains your role name, that entry refers to you.
        - Do NOT materialize yourself with `tool("same_role_name")` or `delegate("same_role_name", ...)`; implement directly.

        What persists:
        - Useful generated programs may be persisted as versioned artifacts and reused on future compatible calls.
        - Tools created through delegation can persist in the registry across sessions.
        - Context state can carry across calls within a session.

        How delegation works:
        - `delegate("name", purpose: ..., deliverable: ..., acceptance: ..., failure_policy: ...)` creates a child tool agent.
        - `tool("name")` materializes an existing tool from the registry.
        - Child agents return Outcomes; inspect with `ok?`, `error?`, `value`, `error_type`, and `error_message`.
        - delegation does NOT grant new capabilities.
        - Do NOT delegate recursively to bypass unavailable capabilities.

        How outcomes work:
        - Dynamic call return values are wrapped as an Outcome object.
        - Prefer `Agent::Outcome.ok(...)` and `Agent::Outcome.error(...)`.
      MODEL
    end

    def _runtime_environment_model_depth1_prompt
      <<~MODEL
        ## Your Environment
        What you have:
        - `context` is working memory.
        - `context[:tools]` is the tool registry metadata.
        - `context[:conversation_history]` is prior structured call history.
        - If a role profile is active, it defines continuity constraints for sibling methods.
        - Identity context: you are this role. If the registry contains your role name, that entry refers to you.
        - Do NOT materialize yourself with `tool("same_role_name")` or `delegate("same_role_name", ...)`; implement directly.

        Call depth:
        - You are at depth 1 (delegated tool execution).
        - Focus on contract execution, not speculative capability expansion.

        How delegation works:
        - `tool("name")` materializes an existing tool from the registry.
        - Any further delegation must stay within runtime capability boundaries.
        - delegation does NOT grant new capabilities.

        How outcomes work:
        - Dynamic call return values are wrapped as an Outcome object.
        - Prefer `Agent::Outcome.ok(...)` and `Agent::Outcome.error(...)`.
      MODEL
    end

    def _runtime_environment_model_worker_prompt(depth:)
      <<~MODEL
        ## Your Environment
        What you have:
        - `context` is working memory and includes tool metadata/history snapshots.
        - Identity context: you are this role. If the registry contains your role name, that entry refers to you.
        - Do NOT materialize yourself with `tool("same_role_name")` or `delegate("same_role_name", ...)`; implement directly.

        Call depth:
        - You are at depth #{depth} (worker mode).
        - Keep execution direct and bounded.

        How outcomes work:
        - Dynamic call return values are wrapped as an Outcome object.
        - delegation does NOT grant new capabilities.
      MODEL
    end

    def _build_user_prompt(name, args, kwargs, call_context: nil)
      current_context = _prompt_memory_context
      depth = call_context&.fetch(:depth, 0) || 0
      self_check = _user_prompt_self_check(depth: depth)
      examples = _user_prompt_examples(name: name, depth: depth)
      active_contract = _active_contract_user_prompt
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

          ## How You Think (strict order)
          Every call follows this sequence. Do not skip steps.

          Step 1: Decompose
          - Separate trigger task from capability.
          - Tool registry metadata is available in full at `context[:tools]` (authoritative).
          - `<known_tools>` is only a preview; both are metadata, not callable objects.
          - Materialize reusable capabilities with `tool("tool_name")` or `delegate("tool_name", ...)`.
          - Ask:
              1. What capability is required?
              2. Is it already available in `context[:tools]`?
              3. If missing, what is the most general useful form?
          - One-step-above translation examples:
              - Trigger: "fetch HN front page" -> Capability: "fetch and parse any URL"
              - Trigger: "convert 100C to F" -> Capability: "convert between units"
          - Capability-fit rule: treat `capabilities` as hints; reason over `purpose`, `methods`, and `deliverable`.

          Step 2: Design Interface
          - Define method name, parameterized inputs, expected return shape, and one acceptance assertion before writing code.

          Step 3: Select Stance
          - Choose Do / Shape / Forge / Orchestrate based on capability reuse and depth policy.
          - Depth 0 + missing general capability -> Forge.
          - Existing matching tool -> Do.
          - Session-local pattern -> Shape.
          - Multi-tool coordination -> Orchestrate.

          Step 4: Implement
          - Write code for the interface you defined.

          Step 5: Self-check
          - Verify implementation truthfulness, capability fit, and result usefulness before finalizing.
          - Use the detailed checklist from the user prompt `<self_check>` block.
          - Reuse-first rule: if a tool already matches capability, reuse or extend it instead of creating near-duplicates.
        NUDGE
      when 1
        <<~NUDGE

          ## How You Think (strict order)
          - You are a Tool executing delegated work: verify whether you can fulfill the task directly with current capabilities.
          - Check `context[:tools]` first before creating anything new.
          - `<known_tools>` is a non-exhaustive preview of the same registry metadata.
          - Registry entries are metadata only; invoke tools via `tool("tool_name")` or explicit `delegate(...)`.
          - If capability is missing, prefer local Shape or typed error; Forge only when the active contract clearly implies a reusable interface.
        NUDGE
      else
        <<~NUDGE

          ## How You Think (strict order)
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

          ## Your Stances
          - Do: execute inline code for this specific call.
          - Shape: solve now while extracting a session-local reusable pattern.
          - Forge: create/refine a durable named tool interface for future reuse.
          - Orchestrate: compose multiple tools for a multi-step outcome.
          - Shape keeps reuse local to this call flow; Forge publishes a durable interface.
          - Default to Forge for reusable/general capabilities and explicit build/create requests.
          - Default to Do for one-off bounded work with low reuse value.
          - If ambiguous between Do and Forge, choose Forge.
          - If ambiguous between Forge and Orchestrate, choose Forge unless orchestration is clearly required.
        POLICY
      when 1
        <<~POLICY

          ## Your Stances
          - Default to Do.
          - Use Shape only when a local pattern helps this call.
          - Forge only when active contract/deliverable clearly implies a reusable interface.
          - Orchestrate is not available at this depth.

          Ambiguity handling:
          - when uncertain, choose Do and add a short Ruby comment explaining the conservative choice.
        POLICY
      else
        <<~POLICY

          ## Your Stances
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
        ## Runtime Hard Constraints
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
        - Be truthful and capability-accurate; never claim an action occurred unless this code actually performed it.
        - Writing to context is internal memory only, not an external side effect.
        - State-key continuity rule:
            1. If context already has a key for the same semantic state, reuse that key.
            2. If no scalar accumulator key exists yet, default to `context[:value]`.
            3. Do not create parallel scalar aliases (for example `:memory`, `:accumulator`, `:calculator_value`) for the same state unless explicitly required.
            4. Setter/readback coherence: if caller sets `obj.foo = x`, prefer `context[:foo]` for that semantic state.
        - `context[:tools]` entries are metadata; query them for capability-fit and materialize tools via `tool(...)`/`delegate(...)`.
        - `context[:conversation_history]` is structured call history; for source follow-ups, read it first and cite concrete refs when available.
        - Never infer or fabricate provenance if history refs are missing; return explicit unknown/missing-source response.
        - Outcome constructors available: Agent::Outcome.ok(...), Agent::Outcome.error(...), Agent::Outcome.call(value=nil, ...).
        - Prefer Agent::Outcome.ok/error as canonical forms; Agent::Outcome.call is a tolerant success alias.
        - Outcome API idioms: use `outcome.ok?` / `outcome.error?` for branching, then `outcome.value` or `outcome.error_message`. (`success?`/`failure?` are tolerated aliases.)
        - For tool composition, preserve contract shapes (for example, pass RSS parser raw feed string, not fetch envelope Hash).
        - When consuming tool output hashes, handle both symbol and string keys unless you explicitly normalized keys.
        - External-data success invariant: if code fetches/parses remote data and returns success, include provenance envelope.
        - Provenance envelope shape (tolerant key types): `provenance: { sources: [{ uri:, fetched_at:, retrieval_tool:, retrieval_mode: ("live"|"cached"|"fixture") }] }`.
        - delegation does NOT grant new capabilities; child tools inherit the same runtime/tooling limits.
        - Do NOT delegate recursively to bypass unavailable capabilities; return typed non-retriable error instead.
        - If output is structurally valid but not useful for caller intent, return `Agent::Outcome.error(error_type: "low_utility", ...)`.
        - Guidance-only prose where concrete items were requested is `low_utility`, not success.
        - If request crosses this Tool's boundary, return `Agent::Outcome.error(error_type: "wrong_tool_boundary", ...)`.
        - Compare active `intent_signature` with Tool purpose/capabilities; on mismatch, prefer `wrong_tool_boundary`.
        - If non-stdlib gems are required, declare minimal `dependencies`; keep outputs/context JSON-serializable.
      RULES
    end

    def _design_quality_prompt(depth:)
      shared = <<~RULES
        Tool Design Quality and Delegation Discipline:
        - Infer what methods and behaviors are natural for role '#{@role}'.
        - Method names should be intuitive verbs or queries a caller would expect for this role.
        - Write clean, focused code that fulfills the active intent/contract.
        - Initialize local accumulators before appending (for example `lines = []`) before calling `<<`/`push`.
        - Parameterize inputs when it improves clarity and reuse.
        - Do NOT over-generalize into frameworks or speculative abstractions.
        - Do NOT mutate Agent/Tool objects with metaprogramming (for example `define_singleton_method`); express behavior through normal generated methods and tool/delegate invocation paths.
      RULES

      depth_rules = case depth
                    when 0
                      <<~RULES
                        - Prefer reusable, parameterized interfaces.
                        - Generalize one step above the immediate task (for example, `fetch_hn_front_page` -> `fetch_url(url)`).
                        - Parameterize obvious inputs (url, query, filepath, etc.); e.g., prefer fetch_url(url) over fetch_specific_article().
                        - At depth 0, for general capabilities (HTTP fetch/parsing/file I/O/text transform), prefer Forge even if direct code is short.
                        - Tool registry is authoritative at `context[:tools]`. Query it directly to find capability-fit candidates.
                        - Reuse by materializing with `tool("name")` (or explicit `delegate(...)`), not by calling metadata entries as executable objects.
                        - When delegating, prefer explicit contracts (`purpose:`, `deliverable:`, `acceptance:`, `failure_policy:`).
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
        - [Truthfulness] Did my code perform every action I described in `result`?
        - [Truthfulness] Am I returning real computed data (not placeholder/example content)?
        - [Failure handling] If blocked or failed, did I return typed `Agent::Outcome.error(...)`?
        - [Data quality] If output is empty/junk or guidance-only where concrete items were requested, did I return `low_utility`?
        - [Provenance] For external-data success, did I include provenance sources + retrieval_mode?
        - [History] For source follow-ups, did I cite concrete refs from `context[:conversation_history]` or explicitly state unknown?
        - [Stance fit] Does my stance match current depth policy?
      CHECK

      depth_checks = case depth
                     when 0
                       <<~CHECK.chomp
                         - [Depth 0 design] Did I separate trigger from capability and check existing tools before forging?
                         - [Depth 0 design] If forging/delegating, is the interface parameterized and delegation justified?
                       CHECK
                     when 1
                       <<~CHECK.chomp
                         - [Depth 1 execution] Did I default to direct execution unless local Shape was clearly useful?
                         - [Depth 1 execution] If I forged/delegated, did the active contract clearly require it?
                       CHECK
                     else
                       <<~CHECK.chomp
                         - [Worker mode] Did I keep execution direct and avoid creating new tools/delegations?
                       CHECK
                     end

      "#{base}\n#{depth_checks}"
    end

    def _known_tools_system_prompt
      <<~TOOLS
        Tool Registry Snapshot:
        #{_known_tools_prompt.rstrip}
        #{_known_tools_system_usage_hint.rstrip}
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
        - `context[:tools]` is the authoritative registry metadata: `{ "tool_name" => { purpose:, methods:, capabilities:, ... } }`.
        - Match by capability-fit (`purpose` + `methods` + `deliverable`; treat `capabilities` tags as hints).
        - Do NOT call values from `context[:tools]` directly; they are metadata, not executable objects.
        - To reuse a known tool, materialize it with `tool("tool_name")` (preferred) or `delegate("tool_name", ...)`.
        </known_tools_usage>
      HINT
    end

    def _known_tools_system_usage_hint
      <<~HINT
        <known_tools_system_usage>
        - Do NOT call values from `context[:tools]` directly; they are metadata, not executable objects.
        - To reuse a known tool, materialize it with `tool("tool_name")` (preferred) or `delegate("tool_name", ...)`.
        </known_tools_system_usage>
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

      scorecards.each_value do |entry|
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

      "calls=#{calls}, success_rate=#{success_count.to_f.fdiv(calls).round(2)}"
    end

    def _extract_tool_degraded_caution(metadata)
      decision = nil
      if metadata.is_a?(Hash)
        decision = metadata[:lifecycle_decision] || metadata["lifecycle_decision"]
        if decision.nil?
          scorecards = metadata[:version_scorecards] || metadata["version_scorecards"]
          if scorecards.is_a?(Hash)
            scorecards.each_value do |entry|
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
          <pattern kind="interface_first_forge">
          ```ruby
          # Thinking
          # Decompose: need reusable HTTP fetch capability.
          # Design: fetch_url(url:, headers: {}) -> { status:, body:, url: }.
          # Stance: Forge (general capability at depth 0).
          fetcher = delegate(
            "web_fetcher",
            purpose: "fetch content from urls",
            deliverable: { type: "object", required: ["status", "body", "url"] },
            acceptance: [{ assert: "status/body/url are present" }],
            failure_policy: { on_error: "return_error" }
          )

          target_url = kwargs[:url] || args.first
          analysis = fetcher.fetch_url(url: target_url, headers: kwargs.fetch(:headers, {}))
          result = analysis.ok? ? analysis.value : Agent::Outcome.error(
            error_type: analysis.error_type,
            error_message: analysis.error_message,
            retriable: analysis.retriable,
            tool_role: @role,
            method_name: "#{name}"
          )
          ```
          </pattern>

          <pattern kind="orchestrate_existing_tools">
          ```ruby
          # Thinking
          # Decompose: need two capabilities (fetch + translate).
          # Design: orchestrate existing tool interfaces; no new tool.
          # Stance: Orchestrate.
          registry = context[:tools] || {}
          unless registry.key?("web_fetcher") && registry.key?("translator")
            result = Agent::Outcome.error(
              error_type: "missing_capability",
              error_message: "web_fetcher and translator must be available in tool registry",
              retriable: false,
              tool_role: @role,
              method_name: "#{name}"
            )
            return
          end

          target_url = kwargs[:url] || args.first
          fetcher = tool("web_fetcher")
          translator = tool("translator")
          fetched = fetcher.fetch_url(url: target_url)

          unless fetched.ok?
            result = Agent::Outcome.error(
              error_type: fetched.error_type,
              error_message: fetched.error_message,
              retriable: fetched.retriable,
              tool_role: @role,
              method_name: "#{name}"
            )
            return
          end

          payload = fetched.value
          body = payload[:body] || payload["body"] || ""
          title = kwargs[:title] || body.lines.first.to_s.strip
          translated = translator.translate(title, to: kwargs.fetch(:language, "es"))
          result = translated.ok? ? translated.value : Agent::Outcome.error(
            error_type: translated.error_type,
            error_message: translated.error_message,
            retriable: translated.retriable,
            tool_role: @role,
            method_name: "#{name}"
          )
          ```
          </pattern>

          <pattern kind="stateful_role_continuity">
          ```ruby
          # Thinking
          # Decompose: arithmetic on shared role state.
          # Design: decrement(amount) -> numeric value.
          # Stance: Do (stateful role method).
          current = context[:value] || 0
          delta = kwargs[:amount] || args.first || 1
          context[:value] = current - delta.to_f
          result = context[:value]
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
