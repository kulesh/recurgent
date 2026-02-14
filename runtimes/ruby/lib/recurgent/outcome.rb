# frozen_string_literal: true

class Agent
  class Outcome
    attr_reader :status, :value, :error_type, :error_message, :retriable, :specialist_role, :method_name

    def self.ok(value:, specialist_role:, method_name:)
      new(status: :ok, specialist_role: specialist_role, method_name: method_name, value: value)
    end

    def self.error(error_type:, error_message:, retriable:, specialist_role:, method_name:)
      new(
        status: :error,
        specialist_role: specialist_role,
        method_name: method_name,
        error_type: error_type,
        error_message: error_message,
        retriable: retriable
      )
    end

    def initialize(status:, specialist_role:, method_name:, value: nil, error_type: nil, error_message: nil, retriable: false)
      @status = status
      @value = value
      @error_type = error_type
      @error_message = error_message
      @retriable = retriable
      @specialist_role = specialist_role
      @method_name = method_name
    end

    def ok?
      @status == :ok
    end

    def error?
      !ok?
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
        specialist_role: @specialist_role,
        method_name: @method_name
      }
    end

    def to_s
      return @value.to_s if ok?

      "[#{@error_type}] #{@error_message}"
    end

    def inspect
      return @value.inspect if ok?

      "#<Agent::Outcome status=:error error_type=#{@error_type.inspect} role=#{@specialist_role.inspect} method=#{@method_name.inspect}>"
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
  end
end
