# frozen_string_literal: true

class Agent
  # Agent::ToolRegistryIntegrity — guardrail checks for executable leakage in tool metadata.
  module ToolRegistryIntegrity
    private

    def _enforce_tool_registry_integrity!(method_name:, phase:)
      registry = @context[:tools]
      return if registry.nil?
      raise ToolRegistryViolationError, "context[:tools] must be a Hash" unless registry.is_a?(Hash)

      executable_paths = _tool_registry_executable_paths(registry, path: "context[:tools]")
      return if executable_paths.empty?

      raise ToolRegistryViolationError,
            "Tool registry metadata cannot store executable objects " \
            "(#{phase} #{@role}.#{method_name}): #{executable_paths.join(", ")}"
    end

    def _tool_registry_executable_paths(value, path:)
      return [path] if _tool_registry_executable_value?(value)
      return _tool_registry_array_executable_paths(value, path: path) if value.is_a?(Array)
      return _tool_registry_hash_executable_paths(value, path: path) if value.is_a?(Hash)

      []
    end

    def _tool_registry_array_executable_paths(array, path:)
      array.each_with_index.flat_map do |entry, index|
        _tool_registry_executable_paths(entry, path: "#{path}[#{index}]")
      end
    end

    def _tool_registry_hash_executable_paths(hash, path:)
      hash.flat_map do |key, entry|
        child_path = "#{path}[#{key.inspect}]"
        _tool_registry_executable_paths(entry, path: child_path)
      end
    end

    def _tool_registry_executable_value?(value)
      return true if _tool_registry_explicit_executable_type?(value)
      return false if _tool_registry_plain_metadata_value?(value)

      value.respond_to?(:call)
    end

    def _tool_registry_explicit_executable_type?(value)
      value.is_a?(Proc) || value.is_a?(Method) || value.is_a?(UnboundMethod) || value.is_a?(Agent)
    end

    def _tool_registry_plain_metadata_value?(value)
      case value
      when nil, String, Numeric, Symbol, TrueClass, FalseClass
        true
      else
        false
      end
    end
  end
end
