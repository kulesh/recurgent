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
          - Tool registry snapshot is included below as `<known_tools>`; use it for reuse-first decisions.
          - `<known_tools>` is registry metadata, not callable objects.
          - To invoke a known tool, use `tool("tool_name")` (preferred) or `delegate("tool_name", ...)`.
          - Before choosing stance, briefly decompose:
              1. What capability is required? (e.g., HTTP fetch, parsing, summarization)
              2. Is that capability already available in known tools/context?
              3. If missing, what is the most general useful form of the capability?
          - Naming nudge:
              prefer names that reflect capability and reuse potential rather than the immediate trigger phrasing.
          - Reuse-first rule:
              if an existing tool already matches capability, reuse or extend it instead of creating a near-duplicate.
        NUDGE
      when 1
        <<~NUDGE

          Decomposition Nudge:
          - You are a Tool executing delegated work: verify whether you can fulfill the task directly with current capabilities.
          - Check `<known_tools>` and context before creating anything new.
          - `<known_tools>` entries are metadata only; invoke tools via `tool("tool_name")` or explicit `delegate(...)`.
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
          - Rule-of-3 repetition is for domain-specific tasks, not general capabilities.
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
        - `context[:conversation_history]` is available as a structured Array of prior call records; prefer direct Ruby filtering/querying when needed.
        - Conversation-history records are additive; treat optional fields defensively (`record[:field] || record["field"]`).
        - Outcome constructors available: Agent::Outcome.ok(...), Agent::Outcome.error(...), Agent::Outcome.call(value=nil, ...).
        - Prefer Agent::Outcome.ok/error as canonical forms; Agent::Outcome.call is a tolerant success alias.
        - Outcome API idioms: use `outcome.ok?` / `outcome.error?` for branching, then `outcome.value` or `outcome.error_message`. (`success?`/`failure?` are tolerated aliases.)
        - For tool composition, preserve contract shapes: pass only fields expected by the downstream method (for example, RSS parser gets raw feed string, not fetch envelope Hash).
        - When consuming tool output hashes, handle both symbol and string keys unless you explicitly normalized keys.
        - For HTTP fetch operations, prefer https endpoints and handle 3xx redirects with a bounded hop count before failing.
        - You may require Ruby standard library (net/http, json, date, socket, etc.) but NOT external gems.
        - If your design needs non-stdlib gems, declare each one in `dependencies`; keep declarations minimal and non-speculative.
        - delegation does NOT grant new capabilities; child tools inherit the same runtime/tooling limits.
        - Do NOT delegate recursively to bypass unavailable capabilities.
        - If blocked by unavailable capability, return a typed non-retriable error outcome instead of fake success.
        - If output is structurally valid but not useful for caller intent, return `Agent::Outcome.error(error_type: "low_utility", ...)` instead of `Outcome.ok` with placeholder status.
        - If request crosses this Tool's boundary, return `Agent::Outcome.error(error_type: "wrong_tool_boundary", ...)` with metadata such as `boundary_axes`, `observed_task_shape`, and optional `suggested_split`.
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
                        - Known tools from `<known_tools>` are metadata snapshots. Reuse them by materializing with `tool("name")`, not by reading `context[:tools]` as executable objects.
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
        suffix = methods.empty? ? "" : "\n  methods: [#{methods.join(", ")}]"
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
        - `<known_tools>` lists metadata only (name/purpose/contract hints).
        - Do NOT call values from `context[:tools]` as if they are executable objects.
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
      return persisted if memory.empty?
      return memory if persisted.empty?

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
      merged[:methods] = (_extract_tool_methods(persisted) + _extract_tool_methods(memory)).uniq
      merged[:aliases] = (_extract_tool_aliases(persisted) + _extract_tool_aliases(memory)).uniq
      merged
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

          <pattern kind="reuse_known_tool">
          ```ruby
          # Reuse from registry: materialize the known tool, do not read context[:tools] as executable.
          web_fetcher = tool("web_fetcher")
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

      <<~CONTRACT
        <active_contract>
        <purpose>#{@delegation_contract[:purpose].inspect}</purpose>
        <deliverable>#{@delegation_contract[:deliverable].inspect}</deliverable>
        <acceptance>#{@delegation_contract[:acceptance].inspect}</acceptance>
        <failure_policy>#{@delegation_contract[:failure_policy].inspect}</failure_policy>
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

      <<~PROMPT

        Tool Builder Delegation Contract:
        - purpose: #{@delegation_contract[:purpose].inspect}
        - deliverable: #{@delegation_contract[:deliverable].inspect}
        - acceptance: #{@delegation_contract[:acceptance].inspect}
        - failure_policy: #{@delegation_contract[:failure_policy].inspect}
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
