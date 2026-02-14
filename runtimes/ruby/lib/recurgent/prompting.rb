# frozen_string_literal: true

class Agent
  # Agent::Prompting — system/user prompt construction, tool schema, delegation contract guidance.
  # Reads: @role, @context, @delegation_contract
  module Prompting
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
            parameterize obvious inputs (url, query, filepath, etc.)
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

      <<~PROMPT
        #{action_desc}

        Your current memory (context): #{current_context.inspect}
        #{contract_guidance}

        What Ruby code should be executed? Remember:
        - You're a #{@role}, so implement appropriate behavior
        - Store persistent data in context (a Hash with symbol keys, e.g. context[:value])
        - Return a GeneratedProgram payload with `code` and optional `dependencies`
        - Use 'result' variable for the raw domain value you want to return inside `code`

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
  end
end
