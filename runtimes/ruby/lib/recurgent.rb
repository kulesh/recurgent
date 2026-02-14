# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require_relative "recurgent/dependency_manifest"
require_relative "recurgent/environment_manager"
require_relative "recurgent/generated_program"
require_relative "recurgent/outcome"
require_relative "recurgent/providers"
require_relative "recurgent/prompting"
require_relative "recurgent/observability"
require_relative "recurgent/dependencies"
require_relative "recurgent/runtime_config"
require_relative "recurgent/call_state"
require_relative "recurgent/worker_executor"
require_relative "recurgent/worker_supervisor"
require_relative "recurgent/preparation_ticket"
require_relative "recurgent/worker_execution"

# An Agent object intercepts all method calls, asks an LLM what Ruby code
# to run, then eval's that code in its own context. The agent's "role"
# (e.g. "calculator", "assistant") is passed to the LLM so it knows what
# kind of specialist it's supposed to be.
#
# The magic is in Ruby's method_missing. When you call calculator.sum,
# Ruby can't find a `sum` method, so it calls method_missing instead.
# We use that hook to send the method name + args to an LLM, ask it to write the
# corresponding Ruby code (e.g. "a function that sums the args") and execute
# whatever code it returns.
#
# == How state works
#
# All persistent state lives in @context, a plain Hash. The LLM-generated
# code reads and writes this hash (via a local variable `context` that
# _execute_code sets up in the eval binding). Instance variables (@foo)
# are reserved for Agent's own machinery and are invisible to
# method_missing — Ruby resolves @foo directly, no method dispatch needed.
#
# == Provider abstraction
#
# The LLM call is delegated to a provider object (see Agent::Providers).
# Provider is auto-detected from the model name, or set explicitly:
#
#   Agent.for("calculator")                              # default: Anthropic
#   Agent.for("calculator", model: "gpt-4o")             # auto-detected: OpenAI
#   Agent.for("calculator", model: "local", provider: :openai)  # explicit
#
class Agent
  VERSION = "0.1.0"
  DEFAULT_MODEL = "claude-sonnet-4-5-20250929"
  DEFAULT_MAX_GENERATION_ATTEMPTS = 2
  DEFAULT_PROVIDER_TIMEOUT_SECONDS = 120.0
  DEFAULT_DELEGATION_BUDGET = 8
  DEFAULT_GEM_SOURCES = ["https://rubygems.org"].freeze
  DEFAULT_SOURCE_MODE = "public_only"
  CALL_STACK_KEY = :__recurgent_call_stack
  RUNTIME_NAME = "ruby"
  DELEGATION_CONTRACT_FIELDS = %i[purpose deliverable acceptance failure_policy].freeze
  class Error < StandardError; end
  class ProviderError < Error; end
  class InvalidCodeError < ProviderError; end
  class InvalidDependencyManifestError < ProviderError; end
  class DependencyManifestIncompatibleError < ProviderError; end
  class DependencyPolicyViolationError < ProviderError; end
  class DependencyResolutionError < ProviderError; end
  class DependencyInstallError < ProviderError; end
  class DependencyActivationError < ProviderError; end
  class WorkerCrashError < Error; end
  class NonSerializableResultError < Error; end
  class EnvironmentPreparingError < Error; end
  class TimeoutError < ProviderError; end
  class ExecutionError < Error; end
  class BudgetExceededError < Error; end

  # Model name prefixes that route to the OpenAI provider.
  OPENAI_MODEL_PATTERN = /\A(gpt-|o[134]-|chatgpt-)/
  ERROR_TYPE_BY_CLASS = [
    [BudgetExceededError, "budget_exceeded"],
    [TimeoutError, "timeout"],
    [InvalidCodeError, "invalid_code"],
    [InvalidDependencyManifestError, "invalid_dependency_manifest"],
    [DependencyManifestIncompatibleError, "dependency_manifest_incompatible"],
    [DependencyPolicyViolationError, "dependency_policy_violation"],
    [DependencyResolutionError, "dependency_resolution_failed"],
    [DependencyInstallError, "dependency_install_failed"],
    [DependencyActivationError, "dependency_activation_failed"],
    [EnvironmentPreparingError, "environment_preparing"],
    [WorkerCrashError, "worker_crash"],
    [NonSerializableResultError, "non_serializable_result"],
    [ProviderError, "provider"]
  ].freeze
  RETRIABLE_ERROR_TYPES = %w[
    timeout
    provider
    invalid_code
    dependency_install_failed
    dependency_activation_failed
    environment_preparing
    worker_crash
  ].freeze

  include Prompting
  include Observability
  include Dependencies
  include WorkerExecution

  # XDG-compliant default path for the JSONL call log.
  def self.default_log_path
    state_home = ENV.fetch("XDG_STATE_HOME", File.join(Dir.home, ".local", "state"))
    File.join(state_home, "recurgent", "recurgent.jsonl")
  end

  def self.for(role, purpose: nil, deliverable: nil, acceptance: nil, failure_policy: nil, delegation_contract: nil, **)
    contract, source = _compose_delegation_contract(
      delegation_contract,
      purpose: purpose,
      deliverable: deliverable,
      acceptance: acceptance,
      failure_policy: failure_policy
    )
    new(role, **, delegation_contract: contract, delegation_contract_source: source)
  end

  def self.prepare(role, dependencies: nil, timeout_seconds: nil, **options)
    ticket = PreparationTicket.new
    Thread.new do
      agent = self.for(role, **options)
      agent.send(:_prepare_specialist_environment!, dependencies: dependencies, prep_ticket_id: ticket.id)
      ticket._resolve(agent: agent)
    rescue StandardError => e
      outcome = Outcome.error(
        error_type: "environment_preparing",
        error_message: "Environment preparation failed for #{role}: #{e.message}",
        retriable: true,
        specialist_role: role,
        method_name: "prepare"
      )
      ticket._reject(outcome: outcome)
    end
    ticket.await(timeout: timeout_seconds) if timeout_seconds
    ticket
  end

  def self._compose_delegation_contract(explicit_contract, **fields)
    _validate_delegation_contract_type!(explicit_contract)
    declared = fields.compact
    return [nil, "none"] if explicit_contract.nil? && declared.empty?
    return [explicit_contract, "hash"] if declared.empty?
    return [declared, "fields"] if explicit_contract.nil?

    [explicit_contract.merge(declared), "merged"]
  end

  def self._validate_delegation_contract_type!(value)
    return if value.nil? || value.is_a?(Hash)

    raise ArgumentError, "delegation_contract must be a Hash or nil"
  end

  def initialize(role, **options)
    config = _resolve_initialize_config(options)

    @role = role
    @model_name = config[:model]
    @provider = _build_provider(config[:model], config[:provider])
    @context = {}
    @verbose, @log, @debug = config.values_at(:verbose, :log, :debug)
    @max_generation_attempts, @provider_timeout_seconds, @delegation_budget = _resolve_runtime_limits(config)
    @delegation_contract, @delegation_contract_source = _resolve_delegation_contract(config)
    @runtime_config = Agent.runtime_config
    @environment_manager = nil
    @env_manifest = nil
    @env_id = nil
    @worker_supervisor = nil
    @prep_ticket_id = nil
    @trace_id = _validate_trace_id(config[:trace_id] || _new_trace_id)
    @log_dir_exists = false
  end

  # -- The metaprogramming core -----------------------------------------------
  #
  # Ruby calls method_missing when a method isn't defined on the object.
  # Since Agent defines almost nothing, nearly every call lands here.
  #
  # Ruby's setter syntax (obj.foo = val) is actually a method call to `foo=`,
  # so we detect the trailing "=" to distinguish setters from regular calls.
  #
  # The *, ** syntax captures both positional and keyword arguments, forwarding
  # them through to the LLM-generated code.

  def method_missing(name, *args, **)
    method_name = name.to_s

    if method_name.end_with?("=")
      # Setters are unambiguous — obj.foo = val always means context[:foo] = val.
      # No LLM call needed. This also ensures child Agents reliably receive
      # data from parents (the parent's LLM code does `result.items = data`).
      @context[method_name.chomp("=").to_sym] = args[0]
    else
      _dispatch_method_call(method_name, *args, **)
    end
  end

  # Dynamic introspection contract:
  # - Always true for setter-like methods (foo=), which map to context writes.
  # - True for context-backed readers after data exists in @context.
  # - False for unknown names; dynamic capability exists but is not statically knowable.
  def respond_to_missing?(name, _include_private = false)
    method_name = name.to_s
    return true if method_name.end_with?("=")

    @context.key?(name.to_sym) || super
  end

  # to_s and inspect are defined directly on Object, so method_missing never
  # sees them. We override to_s to route through the LLM (so `puts calculator`
  # asks the LLM for a string representation), and inspect to return a safe
  # debug string without an LLM call.
  def to_s
    outcome = _dispatch_method_call("to_s")
    return outcome.value.to_s if outcome.ok?

    inspect
  rescue StandardError
    inspect
  end

  def inspect
    "<Agent(#{@role}) context=#{@context.keys}>"
  end

  def remember(**entries)
    entries.each { |key, value| @context[key.to_sym] = value }
    self
  end

  def memory
    @context
  end

  def delegate(role, purpose: nil, deliverable: nil, acceptance: nil, failure_policy: nil, **options)
    raise BudgetExceededError, "Delegation budget exceeded in #{@role}.delegate (remaining: 0)" if @delegation_budget&.zero?

    resolved_budget = options.fetch(:delegation_budget) do
      @delegation_budget.nil? ? nil : @delegation_budget - 1
    end
    explicit_contract = options.delete(:delegation_contract)

    inherited = {
      model: @model_name,
      verbose: @verbose,
      log: @log,
      debug: @debug,
      max_generation_attempts: @max_generation_attempts,
      provider_timeout_seconds: @provider_timeout_seconds,
      delegation_budget: resolved_budget,
      trace_id: @trace_id
    }
    delegate_options = inherited.merge(options)
    Agent.for(
      role,
      purpose: purpose,
      deliverable: deliverable,
      acceptance: acceptance,
      failure_policy: failure_policy,
      delegation_contract: explicit_contract,
      **delegate_options
    )
  end
end

class Agent
  private

  def _resolve_initialize_config(options)
    defaults = {
      model: DEFAULT_MODEL,
      provider: nil,
      verbose: false,
      log: Agent.default_log_path,
      debug: false,
      max_generation_attempts: DEFAULT_MAX_GENERATION_ATTEMPTS,
      provider_timeout_seconds: DEFAULT_PROVIDER_TIMEOUT_SECONDS,
      delegation_budget: DEFAULT_DELEGATION_BUDGET,
      delegation_contract: nil,
      delegation_contract_source: nil,
      trace_id: nil
    }
    unknown_keys = options.keys - defaults.keys
    raise ArgumentError, "Unknown options: #{unknown_keys.join(", ")}" unless unknown_keys.empty?

    defaults.merge(options)
  end

  def _resolve_runtime_limits(config)
    [
      _validate_max_generation_attempts(config[:max_generation_attempts]),
      _validate_provider_timeout_seconds(config[:provider_timeout_seconds]),
      _validate_delegation_budget(config[:delegation_budget])
    ]
  end

  def _resolve_delegation_contract(config)
    contract = _normalize_delegation_contract(config[:delegation_contract])
    source = _normalize_delegation_contract_source(config[:delegation_contract_source], contract)
    [contract, source]
  end

  # Picks the right provider based on model name or explicit hint.
  def _build_provider(model, hint)
    kind = hint || (model.match?(OPENAI_MODEL_PATTERN) ? :openai : :anthropic)
    case kind
    when :openai then Providers::OpenAI.new
    when :anthropic then Providers::Anthropic.new
    else raise ArgumentError, "Unknown provider: #{kind}"
    end
  end

  # The main dispatch: build prompts, ask LLM for code, execute it.
  # Only handles method calls — setters are handled directly in method_missing.
  def _dispatch_method_call(name, *args, **kwargs)
    system_prompt = _build_system_prompt
    user_prompt = _build_user_prompt(name, args, kwargs)
    _with_call_frame do |call_context|
      _execute_dynamic_call(name, args, kwargs, system_prompt, user_prompt, call_context)
    end
  end

  # eval runs the LLM-generated code string in a binding that has access to:
  #   context  — @context hash (read/write persistent state)
  #   args     — positional arguments from the method call
  #   kwargs   — keyword arguments from the method call
  #   Agent — the class itself (so generated code can create child objects)
  #   result   — starts nil; the code sets this to its return value
  #
  # The third argument to eval is a filename for stack traces, so errors
  # in generated code show "(agent:calculator.sum)" instead of "(eval)".
  def _execute_code(code, method_name, *args, **kwargs)
    context = @context
    result = nil

    eval(code, binding, "(agent:#{@role}.#{method_name})")

    result
  rescue Agent::Error
    raise
  rescue StandardError => e
    raise ExecutionError, "Execution error in #{@role}.#{method_name}: #{e.message}", cause: e
  end

  # Appends a JSONL entry for one LLM call. In debug mode, includes prompts
  # and context snapshot. Silently rescues — logging must never break the caller.
  def _log_call(log_context)
    return unless @log

    entry = _build_log_entry(log_context)
    encoded_entry = _json_safe(entry)
    _ensure_log_dir
    File.open(@log, "a") { |f| f.puts(JSON.generate(encoded_entry)) }
  rescue StandardError => e
    warn "[AGENT LOG ERROR #{@role}.#{log_context[:method_name]}] #{e.class}: #{e.message}" if @debug
  end

  def _generate_program_with_retry(method_name, system_prompt, user_prompt)
    last_error = nil

    @max_generation_attempts.times do |attempt|
      attempt_number = attempt + 1
      yield attempt_number if block_given?
      attempt_user_prompt = _retry_user_prompt(user_prompt, attempt_number, last_error)

      begin
        payload = @provider.generate_program(
          model: @model_name,
          system_prompt: system_prompt,
          user_prompt: attempt_user_prompt,
          tool_schema: _tool_schema,
          timeout_seconds: @provider_timeout_seconds
        )
        program = GeneratedProgram.from_provider_payload!(method_name: method_name, payload: payload)
        return [program, attempt_number]
      rescue ProviderError => e
        last_error = e
      rescue StandardError => e
        last_error = _normalize_provider_error(method_name, e)
      end

      next unless @debug && attempt < (@max_generation_attempts - 1)

      warn(
        "[AGENT RETRY #{@role}.#{method_name}] " \
        "provider output invalid, retrying (attempt #{attempt_number}/#{@max_generation_attempts})"
      )
    end

    raise last_error || ProviderError.new("Provider failed to generate program for #{@role}.#{method_name}")
  end

  def _retry_user_prompt(base_user_prompt, attempt_number, last_error)
    return base_user_prompt if attempt_number == 1

    <<~PROMPT
      #{base_user_prompt}

      IMPORTANT: Previous generation failed (#{last_error&.message || "invalid provider output"}).
      Retry #{attempt_number}/#{@max_generation_attempts}.
      You MUST return a valid GeneratedProgram payload in the execute_code tool.
      The payload MUST contain non-empty `code` and optional `dependencies` array.
      The `code` MUST assign `result` and MUST NOT be blank.
      If unavailable capability is the blocker, do NOT recurse via delegation.
      Return a typed non-retriable error outcome with error_type "unsupported_capability".
    PROMPT
  end

  def _validate_max_generation_attempts(value)
    return value if value.is_a?(Integer) && value >= 1

    raise ArgumentError, "max_generation_attempts must be an Integer >= 1"
  end

  def _validate_provider_timeout_seconds(value)
    return nil if value.nil?
    return value if value.is_a?(Numeric) && value.positive?

    raise ArgumentError, "provider_timeout_seconds must be a Numeric > 0 or nil"
  end

  def _validate_delegation_budget(value)
    return nil if value.nil?
    return value if value.is_a?(Integer) && value >= 0

    raise ArgumentError, "delegation_budget must be an Integer >= 0 or nil"
  end

  def _normalize_delegation_contract(value)
    return nil if value.nil?

    _validate_delegation_contract_type!(value)
    normalized = _extract_delegation_contract(value)
    return nil if normalized.empty?

    _validate_delegation_contract_purpose!(normalized[:purpose])

    normalized
  end

  def _validate_trace_id(value)
    return value if value.is_a?(String) && !value.strip.empty?

    raise ArgumentError, "trace_id must be a non-empty String"
  end

  def _normalize_provider_error(method_name, error)
    return TimeoutError.new("Provider timeout in #{@role}.#{method_name}: #{error.message}") if _timeout_error?(error)

    ProviderError.new("Provider error in #{@role}.#{method_name}: #{error.message}")
  end

  def _timeout_error?(error)
    return true if defined?(::Timeout::Error) && error.is_a?(::Timeout::Error)
    return true if defined?(::Net::ReadTimeout) && error.is_a?(::Net::ReadTimeout)
    return true if defined?(::Net::OpenTimeout) && error.is_a?(::Net::OpenTimeout)

    error.message.to_s.match?(/\b(timeout|timed out|execution expired)\b/i)
  end

  def _error_outcome_for(method_name, error)
    error_type = ERROR_TYPE_BY_CLASS.find { |klass, _| error.is_a?(klass) }&.last || "execution"
    retriable = RETRIABLE_ERROR_TYPES.include?(error_type)
    Outcome.error(
      error_type: error_type,
      error_message: error.message,
      retriable: retriable,
      specialist_role: @role,
      method_name: method_name
    )
  end

  def _ensure_log_dir
    return if @log_dir_exists

    FileUtils.mkdir_p(File.dirname(@log))
    @log_dir_exists = true
  end

  def _new_trace_id
    SecureRandom.hex(12)
  end

  def _json_safe(value)
    case value
    when String
      _normalize_utf8(value)
    when Array
      value.map { |item| _json_safe(item) }
    when Hash
      value.each_with_object({}) do |(key, item), normalized|
        normalized[_json_safe_hash_key(key)] = _json_safe(item)
      end
    else
      value
    end
  end

  def _normalize_utf8(value)
    normalized = value.dup
    normalized.force_encoding(Encoding::UTF_8)
    return normalized if normalized.valid_encoding?

    normalized.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
  end

  def _json_safe_hash_key(key)
    return _normalize_utf8(key) if key.is_a?(String)
    return key if key.is_a?(Symbol)

    key
  end

  def _validate_delegation_contract_type!(value)
    return if value.is_a?(Hash)

    raise ArgumentError, "delegation_contract must be a Hash or nil"
  end

  def _extract_delegation_contract(value)
    DELEGATION_CONTRACT_FIELDS.each_with_object({}) do |key, normalized|
      next unless value.key?(key) || value.key?(key.to_s)

      normalized[key] = value[key] || value[key.to_s]
    end
  end

  def _validate_delegation_contract_purpose!(value)
    return if value.nil?
    return if value.is_a?(String) && !value.strip.empty?

    raise ArgumentError, "delegation_contract[:purpose] must be a non-empty String when provided"
  end

  def _normalize_delegation_contract_source(source, contract)
    return "none" if contract.nil?
    return source if source.is_a?(String) && !source.strip.empty?

    "hash"
  end

  def _call_stack
    Thread.current[CALL_STACK_KEY] ||= []
  end

  def _with_call_frame
    frame = {
      trace_id: @trace_id,
      call_id: SecureRandom.hex(8),
      parent_call_id: _call_stack.last&.fetch(:call_id, nil),
      depth: _call_stack.length
    }
    _call_stack.push(frame)
    yield frame
  ensure
    _call_stack.pop
  end

  def _execute_dynamic_call(name, args, kwargs, system_prompt, user_prompt, call_context)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    state = _initial_call_state

    state.outcome = _generate_and_execute(name, args, kwargs, system_prompt, user_prompt, state)
    state.outcome
  rescue ProviderError, ExecutionError, BudgetExceededError, WorkerCrashError, NonSerializableResultError => e
    state.error = e
    state.outcome = _error_outcome_for(name, e)
    state.outcome
  ensure
    duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000
    _log_dynamic_call(
      method_name: name,
      args: args,
      kwargs: kwargs,
      duration_ms: duration_ms,
      system_prompt: system_prompt,
      user_prompt: user_prompt,
      call_context: call_context,
      state: state
    )
  end

  def _generate_and_execute(name, args, kwargs, system_prompt, user_prompt, state)
    generated_program, state.generation_attempt = _generate_program_with_retry(name, system_prompt, user_prompt) do |attempt_number|
      state.generation_attempt = attempt_number
    end
    _capture_generated_program_state!(state, generated_program)
    environment_info = _prepare_dependency_environment!(
      method_name: name,
      normalized_dependencies: state.normalized_dependencies
    )
    _capture_environment_state!(state, environment_info)
    _execute_generated_program(
      name,
      state.code,
      args,
      kwargs,
      normalized_dependencies: state.normalized_dependencies,
      environment_info: environment_info,
      state: state
    )
  end

  def _execute_generated_program(name, code, args, kwargs, normalized_dependencies:, environment_info:, state:)
    _print_generated_code(name, code) if @verbose

    if _worker_execution_required?(normalized_dependencies)
      return _execute_generated_program_in_worker(name, code, args, kwargs, environment_info: environment_info,
                                                                            state: state)
    end

    result = _execute_code(code, name, *args, **kwargs)
    result.is_a?(Outcome) ? result : Outcome.ok(value: result, specialist_role: @role, method_name: name)
  end

  def _print_generated_code(name, code)
    puts "[AGENT #{@role}.#{name}] Generated code:"
    puts "=" * 50
    puts code
    puts "=" * 50
  end
end

module Recurgent
  VERSION = Agent::VERSION
  DEFAULT_MODEL = Agent::DEFAULT_MODEL
end
