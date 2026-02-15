# frozen_string_literal: true

class Agent
  class Outcome
    attr_reader :status, :value, :error_type, :error_message, :retriable, :tool_role, :method_name, :metadata

    # Tolerant constructor: supports generated code that uses Outcome.call.
    # Canonical constructors remain .ok and .error.
    def self.call(value = nil, tool_role: nil, method_name: nil, **kwargs, &block)
      resolved_value =
        if block
          block.call
        elsif value.nil? && !kwargs.empty?
          kwargs
        else
          value
        end

      ok(value: resolved_value, tool_role: tool_role, method_name: method_name)
    end

    def self.ok(*args, value: nil, tool_role: nil, method_name: nil, **kwargs)
      value = args.first if !args.empty? && value.nil?
      resolved_tool_role, resolved_method_name = _resolve_context(tool_role: tool_role, method_name: method_name)
      resolved_value = _resolve_ok_value(value: value, extra: kwargs)
      new(status: :ok, tool_role: resolved_tool_role, method_name: resolved_method_name, value: resolved_value)
    end

    def self.error(
      *args,
      error_type: nil,
      error_message: nil,
      retriable: false,
      tool_role: nil,
      method_name: nil,
      **kwargs
    )
      error_type, error_message, retriable, kwargs = _resolve_error_inputs(
        args: args,
        error_type: error_type,
        error_message: error_message,
        retriable: retriable,
        kwargs: kwargs
      )
      resolved_tool_role, resolved_method_name = _resolve_context(tool_role: tool_role, method_name: method_name)
      new(
        status: :error,
        tool_role: resolved_tool_role,
        method_name: resolved_method_name,
        error_type: error_type || _hash_get(kwargs, :error_type) || "execution",
        error_message: error_message || _hash_get(kwargs, :error_message) || "Execution failed",
        retriable: _retriable_flag?(retriable || _hash_get(kwargs, :retriable)),
        metadata: _error_metadata(kwargs)
      )
    end

    # Normalizes raw values or outcome-like hashes into canonical Outcome objects.
    def self.coerce(value, tool_role:, method_name:)
      return value if value.is_a?(Outcome)
      return _coerce_hash(value, tool_role: tool_role, method_name: method_name) if value.is_a?(Hash)

      ok(value: value, tool_role: tool_role, method_name: method_name)
    end

    def initialize(status:, tool_role:, method_name:, value: nil, error_type: nil, error_message: nil, retriable: false, metadata: nil)
      @status = status
      @value = value
      @error_type = error_type
      @error_message = error_message
      @retriable = retriable
      @tool_role = tool_role
      @method_name = method_name
      @metadata = metadata
    end

    def ok?
      @status == :ok
    end

    # Tolerant alias for broader Result-style conventions.
    def success?
      ok?
    end

    def error?
      !ok?
    end

    # Tolerant alias for broader Result-style conventions.
    def failure?
      error?
    end

    def value_or(default = nil)
      ok? ? @value : default
    end

    def to_h
      {
        status: @status,
        value: @value,
        error_type: @error_type,
        error_message: @error_message,
        retriable: @retriable,
        tool_role: @tool_role,
        method_name: @method_name,
        metadata: @metadata
      }
    end

    def to_s
      return @value.to_s if ok?

      "[#{@error_type}] #{@error_message}"
    end

    def inspect
      return @value.inspect if ok?

      "#<Agent::Outcome status=:error error_type=#{@error_type.inspect} role=#{@tool_role.inspect} method=#{@method_name.inspect}>"
    end

    def ==(other)
      return @value == other unless other.is_a?(Outcome)

      to_h == other.to_h
    end

    def method_missing(name, ...)
      return @value.public_send(name, ...) if ok? && @value.respond_to?(name)

      super
    end

    def respond_to_missing?(name, include_private = false)
      (ok? && @value.respond_to?(name, include_private)) || super
    end

    def self._coerce_hash(value, tool_role:, method_name:)
      status = _extract_status(value)
      return _coerce_error_hash(value, tool_role: tool_role, method_name: method_name) if status == :error
      return _coerce_ok_hash(value, tool_role: tool_role, method_name: method_name) if status == :ok

      ok(value: value, tool_role: tool_role, method_name: method_name)
    end

    def self._coerce_error_hash(value, tool_role:, method_name:)
      error(
        error_type: _hash_get(value, :error_type) || "execution",
        error_message: _hash_get(value, :error_message) || "Execution failed",
        retriable: _retriable_flag?(_hash_get(value, :retriable)),
        tool_role: _hash_get(value, :tool_role) || tool_role,
        method_name: _hash_get(value, :method_name) || method_name,
        metadata: _hash_get(value, :metadata)
      )
    end

    def self._coerce_ok_hash(value, tool_role:, method_name:)
      ok(
        value: _hash_get(value, :value),
        tool_role: _hash_get(value, :tool_role) || tool_role,
        method_name: _hash_get(value, :method_name) || method_name
      )
    end

    def self._extract_status(value)
      status = _hash_get(value, :status)
      return nil if status.nil?

      normalized = status.to_s.downcase
      return :ok if normalized == "ok"
      return :error if normalized == "error"

      :unknown
    end

    def self._hash_get(value, key)
      value[key] || value[key.to_s]
    end

    def self._resolve_context(tool_role:, method_name:)
      context = Agent.current_outcome_context
      [tool_role || context[:tool_role] || "unknown_tool", method_name || context[:method_name] || "unknown_method"]
    end

    def self._resolve_ok_value(value:, extra:)
      return value unless value.nil? && !extra.empty?

      extra
    end

    def self._resolve_error_inputs(args:, error_type:, error_message:, retriable:, kwargs:)
      return [error_type, error_message, retriable, kwargs] if args.empty?

      first = args.first
      return _resolve_error_hash_input(first, error_type, error_message, retriable, kwargs) if first.is_a?(Hash)

      resolved_error_type = error_type || first
      resolved_error_message = error_message || args[1]
      resolved_retriable = args[2].nil? ? retriable : args[2]

      [resolved_error_type, resolved_error_message, resolved_retriable, kwargs]
    end

    def self._resolve_error_hash_input(input_hash, error_type, error_message, retriable, kwargs)
      merged = input_hash.merge(kwargs)
      resolved_error_type = error_type || _hash_get(merged, :error_type)
      resolved_error_message = error_message || _hash_get(merged, :error_message)
      resolved_retriable = _hash_get(merged, :retriable).nil? ? retriable : _hash_get(merged, :retriable)
      cleaned_kwargs = merged.reject { |key, _| %w[error_type error_message retriable].include?(key.to_s) }

      [resolved_error_type, resolved_error_message, resolved_retriable, cleaned_kwargs]
    end

    def self._retriable_flag?(value)
      return false if value.nil?

      value == true
    end

    def self._error_metadata(kwargs)
      explicit_metadata = _hash_get(kwargs, :metadata)
      remaining = kwargs.reject { |key, _| key.to_s == "metadata" }
      return explicit_metadata if remaining.empty?
      return remaining if explicit_metadata.nil?
      return explicit_metadata.merge(remaining) if explicit_metadata.is_a?(Hash)

      explicit_metadata
    end
    private_class_method :_coerce_hash, :_coerce_error_hash, :_coerce_ok_hash,
                         :_extract_status, :_hash_get, :_resolve_context,
                         :_resolve_ok_value, :_resolve_error_inputs,
                         :_resolve_error_hash_input, :_retriable_flag?, :_error_metadata
  end
end
