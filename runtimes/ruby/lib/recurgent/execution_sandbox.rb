# frozen_string_literal: true

class Agent
  # Agent::ExecutionSandbox — per-attempt eval receiver for generated code.
  # Isolates method definitions to a disposable object so generated `def ...`
  # cannot leak into Agent method lookup across calls.
  class ExecutionSandbox
    def initialize(agent:, context:, args:, kwargs:)
      @agent = agent
      @context = context
      @args = args
      @kwargs = kwargs
      @result = nil
    end

    def execute(wrapped_code:, filename:)
      instance_eval(wrapped_code, filename)
      @result
    end

    def tool(...)
      @agent.tool(...)
    end

    def delegate(...)
      @agent.delegate(...)
    end

    def remember(**entries)
      @agent.remember(**entries)
    end

    def runtime_context
      @agent.runtime_context
    end

    # Runtime shims consumed by wrapped generated code.
    def __recurgent_context
      @context
    end

    def __recurgent_args
      @args
    end

    def __recurgent_kwargs
      @kwargs
    end

    def __recurgent_set_result(value)
      @result = value
    end
  end
end
