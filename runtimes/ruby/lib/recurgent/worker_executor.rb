# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "securerandom"

class Agent
  class WorkerExecutor
    class WorkerTimeout < StandardError; end
    class WorkerExited < StandardError; end

    IPC_VERSION = 1

    attr_reader :pid

    def initialize(entrypoint_path: nil)
      @entrypoint_path = entrypoint_path || File.join(__dir__, "worker_entrypoint.rb")
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @wait_thr = nil
      @pid = nil
    end

    def start(env_dir:)
      shutdown if alive?

      env = {
        "BUNDLE_GEMFILE" => File.join(env_dir, "Gemfile"),
        "BUNDLE_PATH" => File.join(env_dir, "vendor", "bundle")
      }
      @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(env, RbConfig.ruby, @entrypoint_path)
      @stdin.sync = true
      @stdout.sync = true
      @pid = @wait_thr.pid
      self
    end

    def execute(payload:, timeout_seconds:)
      raise WorkerExited, "worker is not running" unless alive?

      call_id = SecureRandom.hex(8)
      request = payload.merge(ipc_version: IPC_VERSION, call_id: call_id)
      @stdin.puts(JSON.generate(request))
      response_line = _read_response_line(timeout_seconds)
      response = JSON.parse(response_line)
      raise WorkerExited, "worker returned mismatched call_id" unless response["call_id"] == call_id

      response
    rescue JSON::ParserError => e
      raise WorkerExited, "worker returned invalid JSON: #{e.message}"
    rescue IOError, Errno::EPIPE => e
      raise WorkerExited, "worker pipe failure: #{e.message}"
    end

    def alive?
      return false unless @wait_thr

      @wait_thr.alive?
    end

    def shutdown
      return unless @wait_thr

      _terminate_worker
    ensure
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @wait_thr = nil
      @pid = nil
    end

    private

    def _read_response_line(timeout_seconds)
      timeout = timeout_seconds || 30.0
      raise WorkerTimeout, "worker timed out after #{timeout}s" unless @stdout.wait_readable(timeout)

      response_line = @stdout.gets
      raise WorkerExited, "worker exited without response" if response_line.nil?

      response_line
    end

    def _terminate_worker
      _close_io(@stdin)
      _terminate_with("TERM", wait_seconds: 1)
      _terminate_with("KILL", wait_seconds: 1) unless @wait_thr.join(0)
    rescue Errno::ESRCH
      nil
    ensure
      _close_io(@stdout)
      _close_io(@stderr)
    end

    def _terminate_with(signal, wait_seconds:)
      Process.kill(signal, @wait_thr.pid) if @wait_thr.alive?
      @wait_thr.join(wait_seconds)
    end

    def _close_io(io)
      io&.close unless io&.closed?
    end
  end
end
