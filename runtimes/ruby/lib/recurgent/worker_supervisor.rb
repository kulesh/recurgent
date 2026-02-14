# frozen_string_literal: true

class Agent
  class WorkerSupervisor
    DEFAULT_MAX_RESTARTS = 2

    attr_reader :env_id

    def initialize(executor_factory: nil, max_restarts: DEFAULT_MAX_RESTARTS)
      @executor_factory = executor_factory || -> { WorkerExecutor.new }
      @max_restarts = max_restarts
      @executor = nil
      @env_id = nil
      @restart_count = 0
    end

    def execute(env_id:, env_dir:, payload:, timeout_seconds:)
      _ensure_executor(env_id: env_id, env_dir: env_dir)
      response = @executor.execute(payload: payload, timeout_seconds: timeout_seconds)

      {
        status: response["status"],
        value: response["value"],
        context_snapshot: response["context_snapshot"],
        error_type: response["error_type"],
        error_message: response["error_message"],
        worker_pid: @executor.pid,
        worker_restart_count: @restart_count
      }
    rescue WorkerExecutor::WorkerTimeout => e
      _restart_after_failure(env_dir)
      {
        status: "error",
        error_type: "timeout",
        error_message: e.message,
        worker_pid: @executor&.pid,
        worker_restart_count: @restart_count
      }
    rescue WorkerExecutor::WorkerExited => e
      _restart_after_failure(env_dir)
      {
        status: "error",
        error_type: "worker_crash",
        error_message: e.message,
        worker_pid: @executor&.pid,
        worker_restart_count: @restart_count
      }
    end

    def shutdown
      @executor&.shutdown
      @executor = nil
      @env_id = nil
    end

    private

    def _ensure_executor(env_id:, env_dir:)
      return if @executor && @env_id == env_id && @executor.alive?

      @executor&.shutdown
      @executor = @executor_factory.call
      @executor.start(env_dir: env_dir)
      @env_id = env_id
    end

    def _restart_after_failure(env_dir)
      @executor&.shutdown
      @executor = nil
      @restart_count += 1
      return unless @restart_count <= @max_restarts

      @executor = @executor_factory.call
      @executor.start(env_dir: env_dir)
    end
  end
end
