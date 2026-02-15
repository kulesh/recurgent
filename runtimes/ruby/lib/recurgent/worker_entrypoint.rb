# frozen_string_literal: true

require "json"
require_relative "../recurgent"

$stdout.sync = true

def _deep_symbolize(value)
  case value
  when Array
    value.map { |item| _deep_symbolize(item) }
  when Hash
    value.each_with_object({}) do |(key, item), normalized|
      symbolized_key = key.is_a?(String) && key.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/) ? key.to_sym : key
      normalized[symbolized_key] = _deep_symbolize(item)
    end
  else
    value
  end
end

def _encode_value(value)
  if defined?(Agent::Outcome) && value.is_a?(Agent::Outcome)
    { "__recurgent_outcome__" => value.to_h }
  else
    value
  end
end

def _json_roundtrip(value)
  JSON.parse(JSON.generate(value))
rescue JSON::GeneratorError, TypeError
  nil
end

def _json_compatible?(value)
  case value
  when NilClass, TrueClass, FalseClass, Numeric, String
    true
  when Array
    value.all? { |item| _json_compatible?(item) }
  when Hash
    value.all? { |key, item| _json_compatible_key?(key) && _json_compatible?(item) }
  else
    false
  end
end

def _json_compatible_key?(key)
  key.is_a?(String) || key.is_a?(Symbol)
end

while (line = $stdin.gets)
  begin
    request = JSON.parse(line)
    call_id = request["call_id"]
    method_name = request["method_name"]
    role = request["role"]
    code = request["code"]
    args = _deep_symbolize(request["args"] || [])
    kwargs = _deep_symbolize(request["kwargs"] || {})
    context = _deep_symbolize(request["context_snapshot"] || {})
    result = nil

    previous_outcome_context = Thread.current[Agent::OUTCOME_CONTEXT_KEY]
    Thread.current[Agent::OUTCOME_CONTEXT_KEY] = {
      tool_role: role || "worker_tool",
      method_name: method_name || "unknown_method"
    }

    begin
      # rubocop:disable Security/Eval
      eval(code, binding, "(recurgent-worker:#{method_name})")
      # rubocop:enable Security/Eval
    ensure
      Thread.current[Agent::OUTCOME_CONTEXT_KEY] = previous_outcome_context
    end

    encoded_value = _encode_value(result)
    serialized_value = _json_compatible?(encoded_value) ? _json_roundtrip(encoded_value) : nil
    serialized_context = _json_compatible?(context) ? _json_roundtrip(context) : nil

    response =
      if serialized_value.nil? || serialized_context.nil?
        {
          ipc_version: Agent::WorkerExecutor::IPC_VERSION,
          call_id: call_id,
          status: "error",
          error_type: "non_serializable_result",
          error_message: "Worker result or context is not JSON-serializable"
        }
      else
        {
          ipc_version: Agent::WorkerExecutor::IPC_VERSION,
          call_id: call_id,
          status: "ok",
          value: serialized_value,
          context_snapshot: serialized_context
        }
      end
  rescue StandardError => e
    response = {
      ipc_version: Agent::WorkerExecutor::IPC_VERSION,
      call_id: call_id || "unknown",
      status: "error",
      error_type: "execution",
      error_message: "#{e.class}: #{e.message}"
    }
  end

  begin
    $stdout.puts(JSON.generate(response))
  rescue StandardError => e
    fallback = {
      ipc_version: Agent::WorkerExecutor::IPC_VERSION,
      call_id: call_id || "unknown",
      status: "error",
      error_type: "worker_crash",
      error_message: "failed to serialize worker response: #{e.class}: #{e.message}"
    }
    $stdout.puts(JSON.generate(fallback))
  end
end
