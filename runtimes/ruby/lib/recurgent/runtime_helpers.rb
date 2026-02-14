# frozen_string_literal: true

class Agent
  private

  # The JSON schema both providers use to constrain the LLM's output.
  # Anthropic uses it as a tool definition; OpenAI uses it as a
  # json_schema structured output format.
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

  def _build_system_prompt
    contract_guidance = _delegation_contract_prompt
    <<~PROMPT
      You are a helpful AI assistant living inside a Ruby agent called '#{@role}'.
      Someone is interacting with you and you need to respond by generating Ruby code that will be eval'd in your context.

      You have access to 'context' (a Hash) to store and retrieve data.
      Every dynamic call returns an Outcome object to the caller.
      #{contract_guidance}

      Rules:
      - Always respond with valid GeneratedProgram payload via the execute_code tool
      - The payload MUST include `code` and MAY include `dependencies`
      - Implement exactly what the user expects - be helpful and predictable
      - You can access and modify context to store persistent data
      - Make the object behave naturally as a #{@role} would
      - You may require any Ruby standard library (net/http, json, date, socket, etc.) but NOT external gems
      - If your design would need non-stdlib gems, declare each one in `dependencies` and fail with unsupported_capability
      - Keep `dependencies` minimal; do not speculate
      - For dependency-backed execution, results and context must stay JSON-serializable
      - Set the 'result' variable to the raw domain value you want to return (runtime wraps it in Outcome)
      - Do NOT use 'return' statements - just set 'result'
      - Capability boundaries:
          delegation does NOT grant new capabilities
          delegated specialists inherit the same runtime/tooling limits (Ruby stdlib only; no external gems)
          do NOT delegate recursively to bypass unavailable capabilities
          if blocked by unavailable capability, return a typed non-retriable error outcome instead of fake success
      - Delegation and tool shape:
          prefer reusable, parameterized specialists over one-off specialists
          generalize one step above the immediate task (task-adjacent generality)
          example: prefer fetch_url(url) over fetch_specific_article()
          do NOT over-generalize into frameworks or speculative abstractions
          if reuse is unlikely or semantics are unclear, keep scope narrow and explicit
      - For specialist delegation, strongly prefer an explicit contract:
          specialist = delegate(
            "translator",
            purpose: "translate user text accurately",
            deliverable: { type: "string" },
            acceptance: [{ assert: "output is translated text in target language" }],
            failure_policy: { on_error: "return_error" }
          )
          translation = specialist.translate("hello world")
          if translation.ok?
            result = translation.value
          else
            result = "translator failed: \#{translation.error_type}"
          end
      - Delegated outcomes expose: ok?, error?, value, value_or(default), error_type, error_message, retriable.
    PROMPT
  end

  def _build_user_prompt(name, args, kwargs)
    current_context = @context.dup
    action_desc = "Someone called '#{name}' with args #{args.inspect} and kwargs #{kwargs.inspect}"
    contract_guidance = _delegation_contract_prompt
    generality_guidance = _task_adjacent_generality_prompt
    capability_guidance = _capability_constraints_user_prompt

    <<~PROMPT
      #{action_desc}

      Your current memory (context): #{current_context.inspect}
      #{contract_guidance}

      What Ruby code should be executed? Remember:
      - You're a #{@role}, so implement appropriate behavior
      - Store persistent data in context (a Hash with symbol keys, e.g. context[:value])
      - Return a GeneratedProgram payload with `code` and optional `dependencies`
      - Use 'result' variable for the raw domain value you want to return inside `code`
      #{capability_guidance}
      #{generality_guidance}

      For method calls like 'sum', just do the operation:
      ```ruby
      context[:value] = context.fetch(:value, 0) + 1
      result = context[:value]
      ```

      For simple getters like 'value', just return the value:
      ```ruby
      result = context.fetch(:value, 0)
      ```

      To delegate reasoning or external-subtask work, summon a specialist with delegate, define a contract, and prefer parameterized method names that can be reused across similar tasks:
      ```ruby
      specialist = delegate(
        "analyst",
        purpose: "analyze context data and return concise findings",
        deliverable: { type: "object", required: ["summary"] },
        acceptance: [{ assert: "summary is present" }],
        failure_policy: { on_error: "return_error" }
      )
      analysis = specialist.summarize(context[:data])
      result = analysis.ok? ? analysis.value : "analysis failed: \#{analysis.error_type}"
      ```

      If unavailable capability blocks fulfillment, return a typed error outcome:
      ```ruby
      result = Agent::Outcome.error(
        error_type: "unsupported_capability",
        error_message: "Required capability is unavailable in this runtime.",
        retriable: false,
        specialist_role: @role,
        method_name: "#{name}"
      )
      ```
    PROMPT
  end

  def _capability_constraints_user_prompt
    <<~PROMPT.chomp
      - You may require any Ruby standard library (net/http, json, date, socket, etc.) but NOT external gems
      - If non-stdlib gems are required, declare them in `dependencies` (name + optional version constraint) and fail with unsupported_capability
      - If using dependencies, keep returned values and context JSON-serializable
      - Delegation cannot add new runtime capabilities. Child specialists have the same limits.
      - If the task needs unavailable capability, fail fast with typed non-retriable error outcome.
    PROMPT
  end

  def _task_adjacent_generality_prompt
    <<~PROMPT.chomp
      - When creating specialists/methods, prefer task-adjacent reusable interfaces:
          parameterize obvious inputs (url, query, filepath, etc.)
          generalize one level only; avoid speculative generic frameworks
          choose narrow scope when validation/semantics would otherwise be ambiguous
    PROMPT
  end

  def _build_log_entry(log_context)
    entry = _base_log_entry(log_context)
    _add_contract_to_entry(entry)
    _add_outcome_to_entry(entry, log_context[:outcome]) if log_context[:outcome]
    _add_error_to_entry(entry, log_context[:error]) if log_context[:error]
    _add_debug_section(entry, log_context) if @debug
    entry
  end

  def _base_log_entry(log_context)
    {
      timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
      runtime: Agent::RUNTIME_NAME,
      role: @role,
      model: @model_name,
      method: log_context[:method_name],
      args: log_context[:args],
      kwargs: log_context[:kwargs],
      contract_source: @delegation_contract_source,
      code: log_context[:code],
      program_dependencies: log_context[:program_dependencies],
      normalized_dependencies: log_context[:normalized_dependencies],
      duration_ms: log_context[:duration_ms].round(1),
      generation_attempt: log_context[:generation_attempt]
    }.merge(_trace_log_fields(log_context)).merge(_environment_log_fields(log_context))
  end

  def _trace_log_fields(log_context)
    {
      trace_id: log_context[:call_context]&.fetch(:trace_id, nil),
      call_id: log_context[:call_context]&.fetch(:call_id, nil),
      parent_call_id: log_context[:call_context]&.fetch(:parent_call_id, nil),
      depth: log_context[:call_context]&.fetch(:depth, nil)
    }
  end

  def _environment_log_fields(log_context)
    {
      env_id: log_context[:env_id],
      environment_cache_hit: log_context[:environment_cache_hit],
      env_prepare_ms: log_context[:env_prepare_ms],
      env_resolve_ms: log_context[:env_resolve_ms],
      env_install_ms: log_context[:env_install_ms],
      worker_pid: log_context[:worker_pid],
      worker_restart_count: log_context[:worker_restart_count],
      prep_ticket_id: log_context[:prep_ticket_id]
    }
  end

  def _delegation_contract_prompt
    return "" unless @delegation_contract

    <<~PROMPT

      Solver Delegation Contract:
      - purpose: #{@delegation_contract[:purpose].inspect}
      - deliverable: #{@delegation_contract[:deliverable].inspect}
      - acceptance: #{@delegation_contract[:acceptance].inspect}
      - failure_policy: #{@delegation_contract[:failure_policy].inspect}
      Treat this as the active contract for this specialist call.
    PROMPT
  end

  def _add_debug_section(entry, log_context)
    _add_debug_to_entry(
      entry,
      log_context[:system_prompt],
      log_context[:user_prompt],
      log_context[:error]
    )
  end

  def _add_error_to_entry(entry, error)
    entry[:error_class] = error.class.name
    entry[:error_message] = error.message
  end

  def _add_contract_to_entry(entry)
    return unless @delegation_contract

    entry[:contract_purpose] = @delegation_contract[:purpose]
    entry[:contract_deliverable] = @delegation_contract[:deliverable]
    entry[:contract_acceptance] = @delegation_contract[:acceptance]
    entry[:contract_failure_policy] = @delegation_contract[:failure_policy]
  end

  def _add_outcome_to_entry(entry, outcome)
    entry[:outcome_status] = outcome.status
    entry[:outcome_retriable] = outcome.retriable
    entry[:outcome_specialist_role] = outcome.specialist_role
    entry[:outcome_method_name] = outcome.method_name
    if outcome.ok?
      entry[:outcome_value_class] = outcome.value.class.name unless outcome.value.nil?
    else
      entry[:outcome_error_type] = outcome.error_type
      entry[:outcome_error_message] = outcome.error_message
    end
  end

  def _add_debug_to_entry(entry, system_prompt, user_prompt, error)
    entry[:system_prompt] = system_prompt
    entry[:user_prompt] = user_prompt
    entry[:context] = @context.dup
    entry[:error_backtrace] = error.backtrace&.first(10) if error
  end
end
