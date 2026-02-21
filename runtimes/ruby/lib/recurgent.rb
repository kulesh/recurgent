# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require_relative "recurgent/dependency_manifest"
require_relative "recurgent/environment_manager"
require_relative "recurgent/generated_program"
require_relative "recurgent/json_normalization"
require_relative "recurgent/outcome"
require_relative "recurgent/conversation_history_normalization"
require_relative "recurgent/conversation_history"
require_relative "recurgent/outcome_contract_constraints"
require_relative "recurgent/outcome_contract_shapes"
require_relative "recurgent/outcome_contract_validator"
require_relative "recurgent/providers"
require_relative "recurgent/prompting"
require_relative "recurgent/observability_history_fields"
require_relative "recurgent/observability_attempt_fields"
require_relative "recurgent/observability"
require_relative "recurgent/dependencies"
require_relative "recurgent/runtime_config"
require_relative "recurgent/known_tool_ranker"
require_relative "recurgent/tool_store_paths"
require_relative "recurgent/tool_store_intent_metadata"
require_relative "recurgent/tool_store"
require_relative "recurgent/capability_pattern_extractor"
require_relative "recurgent/user_correction_signals"
require_relative "recurgent/pattern_memory_store"
require_relative "recurgent/pattern_prompting"
require_relative "recurgent/proposal_store"
require_relative "recurgent/authority"
require_relative "recurgent/role_profile"
require_relative "recurgent/role_profile_registry"
require_relative "recurgent/role_profile_guard"
require_relative "recurgent/artifact_metrics"
require_relative "recurgent/artifact_trigger_metadata"
require_relative "recurgent/artifact_store"
require_relative "recurgent/artifact_selector"
require_relative "recurgent/artifact_repair"
require_relative "recurgent/persisted_execution"
require_relative "recurgent/tool_maintenance"
require_relative "recurgent/call_state"
require_relative "recurgent/attempt_isolation"
require_relative "recurgent/attempt_failure_telemetry"
require_relative "recurgent/guardrail_outcome_feedback"
require_relative "recurgent/guardrail_code_checks"
require_relative "recurgent/guardrail_policy"
require_relative "recurgent/guardrail_boundary_normalization"
require_relative "recurgent/tool_registry_integrity"
require_relative "recurgent/execution_sandbox"
require_relative "recurgent/delegation_intent"
require_relative "recurgent/delegation_options"
require_relative "recurgent/fresh_outcome_repair"
require_relative "recurgent/fresh_generation"
require_relative "recurgent/call_execution"
require_relative "recurgent/worker_executor"
require_relative "recurgent/worker_supervisor"
require_relative "recurgent/preparation_ticket"
require_relative "recurgent/worker_execution"

# An Agent object intercepts all method calls, asks an LLM what Ruby code
# to run, then eval's that code in an ephemeral execution sandbox. The agent's "role"
# (e.g. "calculator", "assistant") is passed to the LLM so it knows what
# kind of tool it's supposed to be.
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
  DEFAULT_GUARDRAIL_RECOVERY_BUDGET = 1
  DEFAULT_FRESH_OUTCOME_REPAIR_BUDGET = 1
  DEFAULT_PROVIDER_TIMEOUT_SECONDS = 120.0
  DEFAULT_DELEGATION_BUDGET = 8
  DEFAULT_GEM_SOURCES = ["https://rubygems.org"].freeze
  DEFAULT_SOURCE_MODE = "public_only"
  TOOLSTORE_SCHEMA_VERSION = 1
  PROMPT_VERSION = "2026-02-15.depth-aware.v3"
  MAX_REPAIRS_BEFORE_REGEN = 3
  PROMOTION_POLICY_VERSION = "solver_promotion_v1"
  KNOWN_TOOLS_PROMPT_LIMIT = 12
  CONVERSATION_HISTORY_PROMPT_PREVIEW_LIMIT = 3
  DYNAMIC_DISPATCH_METHODS = %w[ask chat discuss host].freeze
  CALL_STACK_KEY = :__recurgent_call_stack
  OUTCOME_CONTEXT_KEY = :__recurgent_outcome_context
  RUNTIME_NAME = "ruby"
  DELEGATION_CONTRACT_FIELDS = %i[purpose deliverable acceptance failure_policy intent_signature].freeze
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
  class ToolRegistryViolationError < Error; end

  class GuardrailRetryExhaustedError < Error
    attr_reader :metadata

    def initialize(message, metadata: {})
      super(message)
      @metadata = metadata
    end
  end

  class OutcomeRepairRetryExhaustedError < Error
    attr_reader :metadata

    def initialize(message, metadata: {})
      super(message)
      @metadata = metadata
    end
  end

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
    [ToolRegistryViolationError, "tool_registry_violation"],
    [GuardrailRetryExhaustedError, "guardrail_retry_exhausted"],
    [OutcomeRepairRetryExhaustedError, "outcome_repair_retry_exhausted"],
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
  TERMINAL_GUARDRAIL_MESSAGE_PATTERNS = [
    /missing credential/i,
    /api key/i,
    /unsupported runtime capability/i,
    /external service unavailable/i
  ].freeze

  include Prompting
  include Observability
  include JsonNormalization
  include ConversationHistory
  include OutcomeContractValidator
  include Dependencies
  include KnownToolRanker
  include ToolStorePaths
  include ToolStore
  include CapabilityPatternExtractor
  include UserCorrectionSignals
  include PatternMemoryStore
  include PatternPrompting
  include ProposalStore
  include Authority
  include RoleProfileRegistry
  include RoleProfileGuard
  include ArtifactMetrics
  include ArtifactStore
  include ArtifactSelector
  include ArtifactRepair
  include PersistedExecution
  include AttemptIsolation
  include AttemptFailureTelemetry
  include GuardrailPolicy
  include GuardrailBoundaryNormalization
  include ToolRegistryIntegrity
  include DelegationIntent
  include DelegationOptions
  include FreshOutcomeRepair
  include FreshGeneration
  include CallExecution
  include WorkerExecution

  # XDG-compliant default path for the JSONL call log.
  def self.default_log_path
    state_home = ENV.fetch("XDG_STATE_HOME", File.join(Dir.home, ".local", "state"))
    File.join(state_home, "recurgent", "recurgent.jsonl")
  end

  def self.default_toolstore_root
    state_home = ENV.fetch("XDG_STATE_HOME", File.join(Dir.home, ".local", "state"))
    File.join(state_home, "recurgent", "tools")
  end

  def self.for(
    role,
    purpose: nil,
    deliverable: nil,
    acceptance: nil,
    failure_policy: nil,
    intent_signature: nil,
    delegation_contract: nil,
    **
  )
    contract, source = _compose_delegation_contract(
      delegation_contract,
      purpose: purpose,
      deliverable: deliverable,
      acceptance: acceptance,
      failure_policy: failure_policy,
      intent_signature: intent_signature
    )
    new(role, **, delegation_contract: contract, delegation_contract_source: source)
  end

  def self.prepare(role, dependencies: nil, timeout_seconds: nil, **options)
    ticket = PreparationTicket.new
    Thread.new do
      agent = self.for(role, **options)
      agent.send(:_prepare_tool_environment!, dependencies: dependencies, prep_ticket_id: ticket.id)
      ticket._resolve(agent: agent)
    rescue StandardError => e
      outcome = Outcome.error(
        error_type: "environment_preparing",
        error_message: "Environment preparation failed for #{role}: #{e.message}",
        retriable: true,
        tool_role: role,
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

  def self.current_outcome_context
    Thread.current[OUTCOME_CONTEXT_KEY] || {}
  end

  def initialize(role, **options)
    config = _resolve_initialize_config(options)
    _configure_runtime_state(role, config)
    _hydrate_tool_registry!
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
  def method_missing(name, *args, **kwargs)
    method_name = name.to_s

    if method_name.end_with?("=")
      # Setters are unambiguous — obj.foo = val always means context[:foo] = val.
      # No LLM call needed. This also ensures child Agents reliably receive
      # data from parents (the parent's LLM code does `result.items = data`).
      @context[method_name.chomp("=").to_sym] = args[0]
      _record_setter_role_profile_observation!(setter_method_name: method_name)
    elsif args.empty? && kwargs.empty? && @context.key?(name.to_sym)
      # Context-backed readers are deterministic readback paths. If caller set
      # obj.foo = x earlier, obj.foo should return x without regenerating code.
      Outcome.ok(value: @context[name.to_sym], tool_role: @role, method_name: method_name)
    else
      _dispatch_method_call(method_name, *args, **kwargs)
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
    _enforce_tool_registry_integrity!(method_name: "remember", phase: "remember")
    self
  end

  def runtime_context
    @context
  end

  def role_profile
    profile = _active_role_profile
    return nil if profile.nil?

    _json_safe(profile)
  end

  def self_model
    model = @self_model
    return _json_safe(_default_self_model_snapshot) if model.nil?

    _json_safe(model.dup)
  end

  def propose(proposal_type:, target:, proposed_diff_summary:, evidence_refs: [], metadata: {})
    _proposal_create(
      proposal_type: proposal_type,
      target: target,
      proposed_diff_summary: proposed_diff_summary,
      evidence_refs: evidence_refs,
      metadata: metadata
    )
  end

  def proposals(status: nil, limit: nil)
    _proposal_list(status: status, limit: limit)
  end

  def proposal(proposal_id)
    _proposal_find(proposal_id)
  end

  def approve_proposal(proposal_id, actor: nil, note: nil)
    resolved_actor = _proposal_actor(actor)
    unless _proposal_mutation_allowed?(actor: resolved_actor)
      return _authority_denied_outcome(method_name: "approve_proposal", actor: resolved_actor,
                                       action: "approve")
    end

    proposal = _proposal_update_status(
      proposal_id: proposal_id,
      status: "approved",
      actor: resolved_actor,
      note: note
    )
    return Outcome.error(error_type: "not_found", error_message: "Proposal '#{proposal_id}' not found", retriable: false) if proposal.nil?

    Outcome.ok(value: proposal, tool_role: @role, method_name: "approve_proposal")
  end

  def reject_proposal(proposal_id, actor: nil, note: nil)
    resolved_actor = _proposal_actor(actor)
    unless _proposal_mutation_allowed?(actor: resolved_actor)
      return _authority_denied_outcome(method_name: "reject_proposal", actor: resolved_actor,
                                       action: "reject")
    end

    proposal = _proposal_update_status(
      proposal_id: proposal_id,
      status: "rejected",
      actor: resolved_actor,
      note: note
    )
    return Outcome.error(error_type: "not_found", error_message: "Proposal '#{proposal_id}' not found", retriable: false) if proposal.nil?

    Outcome.ok(value: proposal, tool_role: @role, method_name: "reject_proposal")
  end

  def apply_proposal(proposal_id, actor: nil, note: nil)
    resolved_actor = _proposal_actor(actor)
    unless _proposal_mutation_allowed?(actor: resolved_actor)
      return _authority_denied_outcome(method_name: "apply_proposal", actor: resolved_actor,
                                       action: "apply")
    end

    proposal = _proposal_find(proposal_id)
    return Outcome.error(error_type: "not_found", error_message: "Proposal '#{proposal_id}' not found", retriable: false) if proposal.nil?

    status = proposal["status"].to_s
    if status != "approved"
      return Outcome.error(
        error_type: "invalid_proposal_state",
        error_message: "Proposal '#{proposal_id}' must be approved before apply (current: #{status}).",
        retriable: false
      )
    end

    mutation = _apply_proposal_mutation(
      proposal: proposal,
      actor: resolved_actor,
      note: note
    )
    return mutation if mutation.is_a?(Outcome) && mutation.error?

    applied = _proposal_update_status(
      proposal_id: proposal_id,
      status: "applied",
      actor: resolved_actor,
      note: note
    )
    if mutation.is_a?(Hash)
      applied["applied_mutation"] = mutation
      _proposal_persist_record(applied)
    end
    Outcome.ok(value: applied, tool_role: @role, method_name: "apply_proposal")
  end

  def tool(role, **options)
    role_name = role.to_s.strip
    _enforce_no_self_materialization!(role_name: role_name, api_name: "tool")
    metadata = _registered_tool_metadata(role_name)
    raise ArgumentError, "Unknown tool '#{role_name}' in #{@role}.tool" unless metadata

    purpose = _tool_metadata_option(options: options, metadata: metadata, key: :purpose)
    deliverable = _tool_metadata_option(options: options, metadata: metadata, key: :deliverable)
    acceptance = _tool_metadata_option(options: options, metadata: metadata, key: :acceptance)
    failure_policy = _tool_metadata_option(options: options, metadata: metadata, key: :failure_policy)
    intent_signature = _tool_metadata_option(options: options, metadata: metadata, key: :intent_signature)

    delegate(
      role_name,
      purpose: purpose,
      deliverable: deliverable,
      acceptance: acceptance,
      failure_policy: failure_policy,
      intent_signature: intent_signature,
      **options
    )
  end

  def delegate(
    role,
    purpose: nil,
    deliverable: nil,
    acceptance: nil,
    failure_policy: nil,
    intent_signature: nil,
    **options
  )
    role_name = role.to_s.strip
    _enforce_no_self_materialization!(role_name: role_name, api_name: "delegate")
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
      guardrail_recovery_budget: @guardrail_recovery_budget,
      fresh_outcome_repair_budget: @fresh_outcome_repair_budget,
      provider_timeout_seconds: @provider_timeout_seconds,
      delegation_budget: resolved_budget,
      trace_id: @trace_id
    }
    runtime_options, ignored_options = _partition_delegate_runtime_options(options)
    delegate_options = inherited.merge(runtime_options)
    _warn_ignored_delegate_options(role: role_name, ignored_options: ignored_options) unless ignored_options.empty?
    tool = Agent.for(
      role_name,
      purpose: purpose,
      deliverable: deliverable,
      acceptance: acceptance,
      failure_policy: failure_policy,
      intent_signature: _resolve_delegate_intent_signature(intent_signature),
      delegation_contract: explicit_contract,
      **delegate_options
    )
    _register_delegated_tool(role: role_name, tool: tool, explicit_purpose: purpose)
    tool
  end

  # Tool objects must evolve through Agent dynamic dispatch, not ad hoc singleton methods.
  # This prevents bypassing persistence, contract validation, and observability lanes.
  def define_singleton_method(...)
    raise ToolRegistryViolationError,
          "Defining singleton methods on Agent instances is not supported; use tool/delegate invocation paths."
  end
end

class Agent
  private

  def _enforce_no_self_materialization!(role_name:, api_name:)
    current_role = @role.to_s.strip
    return unless role_name.casecmp?(current_role)

    raise ToolRegistryViolationError,
          "Self-materialization is not allowed in #{@role}.#{api_name}; " \
          "implement this role directly instead of calling #{api_name}(\"#{role_name}\")."
  end

  def _record_setter_role_profile_observation!(setter_method_name:)
    profile = _active_role_profile
    return if profile.nil?

    constraints = profile[:constraints]
    return unless constraints.is_a?(Hash)

    method_name = setter_method_name.to_s
    return unless constraints.any? do |_constraint_name, constraint|
      next false unless constraint.is_a?(Hash) && constraint[:kind].to_sym == :shared_state_slot

      _role_profile_constraint_applies_to_method?(constraint: constraint, method_name: method_name)
    end

    state_key = method_name.delete_suffix("=")
    return if state_key.empty?

    _role_profile_record_observation(
      kind: :shared_state_slot,
      method_name: method_name,
      value: state_key
    )
  rescue StandardError => e
    warn "[AGENT ROLE PROFILE #{@role}] failed to record setter observation: #{e.class}: #{e.message}" if @debug
  end

  def _resolve_initialize_config(options)
    defaults = {
      model: DEFAULT_MODEL,
      provider: nil,
      verbose: false,
      log: Agent.default_log_path,
      debug: false,
      max_generation_attempts: DEFAULT_MAX_GENERATION_ATTEMPTS,
      guardrail_recovery_budget: DEFAULT_GUARDRAIL_RECOVERY_BUDGET,
      fresh_outcome_repair_budget: DEFAULT_FRESH_OUTCOME_REPAIR_BUDGET,
      provider_timeout_seconds: DEFAULT_PROVIDER_TIMEOUT_SECONDS,
      delegation_budget: DEFAULT_DELEGATION_BUDGET,
      delegation_contract: nil,
      delegation_contract_source: nil,
      role_profile: nil,
      role_profile_version: nil,
      trace_id: nil
    }
    unknown_keys = options.keys - defaults.keys
    raise ArgumentError, "Unknown options: #{unknown_keys.join(", ")}" unless unknown_keys.empty?

    defaults.merge(options)
  end

  def _resolve_runtime_limits(config)
    [
      _validate_max_generation_attempts(config[:max_generation_attempts]),
      _validate_guardrail_recovery_budget(config[:guardrail_recovery_budget]),
      _validate_fresh_outcome_repair_budget(config[:fresh_outcome_repair_budget]),
      _validate_provider_timeout_seconds(config[:provider_timeout_seconds]),
      _validate_delegation_budget(config[:delegation_budget])
    ]
  end

  def _resolve_delegation_contract(config)
    contract = _normalize_delegation_contract(config[:delegation_contract])
    source = _normalize_delegation_contract_source(config[:delegation_contract_source], contract)
    [contract, source]
  end

  def _configure_runtime_state(role, config)
    @role = role
    @model_name = config[:model]
    @provider = _build_provider(config[:model], config[:provider])
    @runtime_config = Agent.runtime_config
    @context = {}
    _hydrate_role_profiles!
    _role_profile_registry_apply!(config[:role_profile], source: "initialize_option") unless config[:role_profile].nil?
    _role_profile_registry_activate!(version: config[:role_profile_version], source: "initialize_option") unless config[:role_profile_version].nil?
    @verbose, @log, @debug = config.values_at(:verbose, :log, :debug)
    @max_generation_attempts, @guardrail_recovery_budget, @fresh_outcome_repair_budget, @provider_timeout_seconds, @delegation_budget =
      _resolve_runtime_limits(config)
    @delegation_contract, @delegation_contract_source = _resolve_delegation_contract(config)
    @environment_manager = nil
    @env_manifest = nil
    @env_id = nil
    @worker_supervisor = nil
    @prep_ticket_id = nil
    @trace_id = _validate_trace_id(config[:trace_id] || _new_trace_id)
    @log_dir_exists = false
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

  def _default_self_model_snapshot
    {
      awareness_level: "l1",
      authority: {
        observe: true,
        propose: true,
        enact: false
      },
      active_contract_version: nil,
      active_role_profile_version: nil,
      execution_snapshot_ref: nil,
      evolution_snapshot_ref: nil
    }
  end

  # Executes LLM-generated code on an ephemeral sandbox receiver.
  #
  # Generated code still gets local `context`, `args`, `kwargs`, and `result`
  # bindings, but method definitions are isolated to the sandbox object so they
  # cannot leak into Agent method lookup across calls.
  def _execute_code(code, method_name, *args, **kwargs)
    wrapped_code = _wrap_generated_code(code)
    sandbox = ExecutionSandbox.new(agent: self, context: @context, args: args, kwargs: kwargs)
    execution_result = nil

    _enforce_tool_registry_integrity!(method_name: method_name, phase: "pre_execution")
    _with_outcome_call_context(method_name, args: args, kwargs: kwargs) do
      execution_result = sandbox.execute(
        wrapped_code: wrapped_code,
        filename: "(agent:#{@role}.#{method_name})"
      )
    end
    _enforce_tool_registry_integrity!(method_name: method_name, phase: "post_execution")
    execution_result
  rescue Agent::Error
    raise
  rescue StandardError, ScriptError => e
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
        _validate_generated_code_syntax!(method_name, program.code)
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

  def _validate_generated_code_syntax!(method_name, code)
    RubyVM::InstructionSequence.compile(_wrap_generated_code(code), "(agent:#{@role}.#{method_name})")
  rescue SyntaxError => e
    raise InvalidCodeError, "Generated code has invalid Ruby syntax in #{@role}.#{method_name}: #{e.message}"
  end

  def _wrap_generated_code(code)
    indented_code = code.lines.map { |line| "  #{line}" }.join
    [
      "__recurgent_result_sentinel = Object.new",
      "context = __recurgent_context",
      "memory = context",
      "args = __recurgent_args",
      "kwargs = __recurgent_kwargs",
      "result = __recurgent_result_sentinel",
      "__recurgent_exec = lambda do",
      indented_code,
      "end",
      "__recurgent_return_value = __recurgent_exec.call",
      "result = __recurgent_return_value if result.equal?(__recurgent_result_sentinel)",
      "__recurgent_set_result(result)"
    ].join("\n")
  end

  def _with_outcome_call_context(method_name, args: [], kwargs: {})
    previous = Thread.current[OUTCOME_CONTEXT_KEY]
    Thread.current[OUTCOME_CONTEXT_KEY] = {
      tool_role: @role,
      method_name: method_name,
      args: args,
      kwargs: kwargs
    }
    yield
  ensure
    Thread.current[OUTCOME_CONTEXT_KEY] = previous
  end

  def _retry_user_prompt(base_user_prompt, attempt_number, last_error)
    return base_user_prompt if attempt_number == 1

    <<~PROMPT
      #{base_user_prompt}

      IMPORTANT: Previous generation failed (#{last_error&.message || "invalid provider output"}).
      Retry #{attempt_number}/#{@max_generation_attempts}.
      You MUST return a valid GeneratedProgram payload in the execute_code tool.
      The payload MUST contain non-empty `code` and optional `dependencies` array.
      The `code` MUST either assign `result` or use `return` to produce a value, and MUST NOT be blank.
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

  def _apply_proposal_mutation(proposal:, actor:, note:)
    proposal_type = proposal["proposal_type"].to_s
    return nil unless proposal_type == "role_profile_update"

    target = proposal["target"]
    metadata = proposal["metadata"]
    action = if metadata.is_a?(Hash) && metadata["action"]
               metadata["action"]
             elsif target.is_a?(Hash) && target["action"]
               target["action"]
             else
               "publish_and_activate"
             end
    normalized_action = action.to_s.strip
    normalized_action = "publish_and_activate" if normalized_action.empty?
    proposal_id = proposal["id"].to_s

    case normalized_action
    when "activate", "rollback"
      version = _proposal_role_profile_version_value(target: target, metadata: metadata)
      return _invalid_proposal_payload_outcome(proposal_id, "missing role profile version for #{normalized_action}") if version.nil?

      applied = if normalized_action == "activate"
                  _role_profile_registry_activate!(
                    version: version,
                    actor: actor,
                    source: "proposal_apply",
                    proposal_id: proposal_id,
                    note: note
                  )
                else
                  _role_profile_registry_rollback!(
                    version: version,
                    actor: actor,
                    source: "proposal_apply",
                    proposal_id: proposal_id,
                    note: note
                  )
                end
      {
        "proposal_type" => proposal_type,
        "action" => normalized_action,
        "active_version" => applied[:version]
      }
    when "publish", "publish_only", "publish_and_activate"
      profile_payload = _proposal_role_profile_payload(target: target, metadata: metadata)
      return nil if profile_payload.nil?

      activate = normalized_action != "publish_only"
      applied = _role_profile_registry_apply!(
        profile_payload,
        activate: activate,
        actor: actor,
        source: "proposal_apply",
        proposal_id: proposal_id,
        note: note
      )
      active = _active_role_profile
      {
        "proposal_type" => proposal_type,
        "action" => normalized_action,
        "published_version" => applied[:version],
        "active_version" => active&.dig(:version)
      }
    else
      _invalid_proposal_payload_outcome(proposal_id, "unsupported role_profile_update action '#{normalized_action}'")
    end
  rescue ArgumentError => e
    _invalid_proposal_payload_outcome(proposal_id, e.message)
  end

  def _proposal_role_profile_payload(target:, metadata:)
    payload = (metadata["role_profile"] || metadata[:role_profile] if metadata.is_a?(Hash))
    payload ||= target["role_profile"] || target[:role_profile] if target.is_a?(Hash)
    payload ||= target if target.is_a?(Hash) && (target.key?("constraints") || target.key?(:constraints))
    return nil unless payload.is_a?(Hash)

    expected_role = _proposal_role_profile_target_role(target: target, metadata: metadata)
    if !expected_role.empty? && expected_role != @role
      raise ArgumentError, "proposal target role '#{expected_role}' does not match current role '#{@role}'"
    end

    payload
  end

  def _proposal_role_profile_target_role(target:, metadata:)
    return target["role"].to_s if target.is_a?(Hash) && target["role"]
    return target[:role].to_s if target.is_a?(Hash) && target[:role]
    return metadata["role"].to_s if metadata.is_a?(Hash) && metadata["role"]
    return metadata[:role].to_s if metadata.is_a?(Hash) && metadata[:role]

    ""
  end

  def _proposal_role_profile_version_value(target:, metadata:)
    value = (metadata["active_version"] || metadata[:active_version] || metadata["version"] || metadata[:version] if metadata.is_a?(Hash))
    value = target["active_version"] || target[:active_version] || target["version"] || target[:version] if value.nil? && target.is_a?(Hash)
    return nil if value.nil?

    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end

  def _invalid_proposal_payload_outcome(proposal_id, message)
    Outcome.error(
      error_type: "invalid_proposal_payload",
      error_message: "Proposal '#{proposal_id}' is invalid: #{message}",
      retriable: false,
      tool_role: @role,
      method_name: "apply_proposal"
    )
  end

  def _normalize_delegation_contract(value)
    return nil if value.nil?

    _validate_delegation_contract_type!(value)
    normalized = _extract_delegation_contract(value)
    return nil if normalized.empty?

    _validate_delegation_contract_purpose!(normalized[:purpose])
    _validate_delegation_contract_intent_signature!(normalized[:intent_signature])

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

  def _error_outcome_for(method_name, error, call_context: nil)
    error_type = _error_type_for_exception(error)
    retriable = RETRIABLE_ERROR_TYPES.include?(error_type)
    payload = {
      error_type: error_type,
      error_message: error.message,
      retriable: retriable,
      tool_role: @role,
      method_name: method_name
    }
    payload[:metadata] = error.metadata if error.respond_to?(:metadata)
    payload = _normalize_top_level_guardrail_exhaustion_payload(payload: payload, error: error, call_context: call_context)
    Outcome.error(payload)
  end

  def _ensure_log_dir
    return if @log_dir_exists

    FileUtils.mkdir_p(File.dirname(@log))
    @log_dir_exists = true
  end

  def _new_trace_id
    SecureRandom.hex(12)
  end

  def _register_delegated_tool(role:, tool:, explicit_purpose:)
    role_name = role.to_s
    registry = @context[:tools]
    registry = @context[:tools] = {} unless registry.is_a?(Hash)

    contract = tool.instance_variable_get(:@delegation_contract)
    purpose = explicit_purpose || contract&.fetch(:purpose, nil) || "purpose unavailable"
    metadata = { purpose: purpose, methods: [], aliases: [] }
    metadata.merge!(_delegated_tool_contract_summary(contract))

    registry[role_name] = metadata
    _enforce_tool_registry_integrity!(method_name: "delegate", phase: "register")
    _persist_tool_registry_entry(role_name, metadata)
  end

  def _registered_tool_metadata(role_name)
    registry = @context[:tools]
    return nil unless registry.is_a?(Hash)

    registry[role_name] || registry[role_name.to_sym]
  end

  def _tool_metadata_field(metadata, key)
    return nil unless metadata.is_a?(Hash)

    metadata[key] || metadata[key.to_s]
  end

  def _tool_metadata_option(options:, metadata:, key:)
    options.key?(key) ? options.delete(key) : _tool_metadata_field(metadata, key)
  end

  def _delegated_tool_contract_summary(contract)
    return {} unless contract.is_a?(Hash)

    summary = contract.slice(:deliverable, :acceptance, :failure_policy, :intent_signature)
    intent = summary.delete(:intent_signature)
    return summary if intent.nil?

    summary.merge(
      intent_signature: intent,
      intent_signatures: [intent.to_s]
    )
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
end

module Recurgent
  VERSION = Agent::VERSION
  DEFAULT_MODEL = Agent::DEFAULT_MODEL
end
