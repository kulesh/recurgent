# frozen_string_literal: true

require "json"

class Agent
  # Agent::WorkerExecution — worker payload, JSON boundary crossing, response decoding.
  # Reads: @role, @context, @provider_timeout_seconds, @worker_supervisor
  module WorkerExecution
    private

    def _worker_execution_required?(normalized_dependencies)
      dependencies = normalized_dependencies || []
      !dependencies.empty?
    end

    def _execute_generated_program_in_worker(method_name, code, args, kwargs, environment_info:, state:)
      payload = _worker_payload(method_name: method_name, code: code, args: args, kwargs: kwargs)
      response = _worker_supervisor.execute(
        env_id: environment_info[:env_id],
        env_dir: environment_info[:env_dir],
        payload: payload,
        timeout_seconds: @provider_timeout_seconds
      )
      _capture_worker_state!(state, response)
      _apply_worker_response!(method_name, response)
    end

    def _worker_payload(method_name:, code:, args:, kwargs:)
      {
        role: @role,
        method_name: method_name,
        code: code,
        args: _json_serializable!(args, "args"),
        kwargs: _json_serializable!(kwargs, "kwargs"),
        context_snapshot: _json_serializable!(@context, "context")
      }
    end

    def _capture_worker_state!(state, response)
      state.worker_pid = response[:worker_pid]
      state.worker_restart_count = response[:worker_restart_count]
    end

    def _apply_worker_response!(method_name, response)
      case response[:status]
      when "ok"
        @context = _deep_symbolize(response.fetch(:context_snapshot, {}))
        value = _decode_worker_value(response[:value], method_name)
        Outcome.coerce(value, tool_role: @role, method_name: method_name)
      when "error"
        _raise_worker_error!(response)
      else
        raise WorkerCrashError, "Worker returned unknown status: #{response[:status].inspect}"
      end
    end

    def _decode_worker_value(value, method_name)
      return value unless value.is_a?(Hash) && value["__recurgent_outcome__"]

      _decode_outcome_value(value["__recurgent_outcome__"], method_name)
    end

    def _decode_outcome_value(encoded, method_name)
      return _decode_ok_outcome(encoded, method_name) if encoded["status"].to_s == "ok"

      _decode_error_outcome(encoded, method_name)
    end

    def _decode_ok_outcome(encoded, method_name)
      Outcome.ok(
        value: encoded["value"],
        tool_role: encoded["tool_role"] || @role,
        method_name: encoded["method_name"] || method_name
      )
    end

    def _decode_error_outcome(encoded, method_name)
      Outcome.error(
        error_type: encoded["error_type"] || "execution",
        error_message: encoded["error_message"] || "Worker returned error outcome",
        retriable: !encoded["retriable"].nil? && encoded["retriable"],
        tool_role: encoded["tool_role"] || @role,
        method_name: encoded["method_name"] || method_name
      )
    end

    def _raise_worker_error!(response)
      error_type = response[:error_type].to_s
      error_message = response[:error_message].to_s
      case error_type
      when "non_serializable_result"
        raise NonSerializableResultError, error_message
      when "timeout"
        raise TimeoutError, error_message
      when "worker_crash"
        raise WorkerCrashError, error_message
      else
        raise ExecutionError, "Worker execution error in #{@role}: #{error_message}"
      end
    end

    def _worker_supervisor
      @worker_supervisor ||= WorkerSupervisor.new
    end

    def _json_serializable!(value, field_name)
      raise NonSerializableResultError, "#{field_name} contains non-JSON-compatible values" unless _json_compatible?(value)

      JSON.parse(JSON.generate(value))
    rescue JSON::GeneratorError, TypeError => e
      raise NonSerializableResultError, "#{field_name} is not JSON-serializable: #{e.message}"
    end

    def _deep_symbolize(value)
      case value
      when Array
        value.map { |item| _deep_symbolize(item) }
      when Hash
        value.each_with_object({}) do |(key, item), normalized|
          normalized[_symbolize_key(key)] = _deep_symbolize(item)
        end
      else
        value
      end
    end

    def _symbolize_key(key)
      return key.to_sym if key.is_a?(String) && key.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)

      key
    end

    def _json_compatible?(value)
      case value
      when NilClass, TrueClass, FalseClass, Numeric, String
        true
      when Array
        value.all? { |item| _json_compatible?(item) }
      when Hash
        value.all? { |key, item| _json_key_compatible?(key) && _json_compatible?(item) }
      else
        false
      end
    end

    def _json_key_compatible?(key)
      key.is_a?(String) || key.is_a?(Symbol)
    end
  end
end
