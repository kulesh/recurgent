# frozen_string_literal: true

require "securerandom"

class Agent
  class PreparationTicket
    attr_reader :id

    def initialize
      @id = SecureRandom.hex(8)
      @status = :pending
      @agent = nil
      @error_outcome = nil
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @ready_callbacks = []
      @error_callbacks = []
    end

    def status
      @mutex.synchronize { @status }
    end

    def agent
      @mutex.synchronize { @agent }
    end

    def await(timeout: nil)
      @mutex.synchronize do
        if timeout
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          while @status == :pending
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            return nil if remaining <= 0

            @condition.wait(@mutex, remaining)
          end
        else
          @condition.wait(@mutex) while @status == :pending
        end

        @status == :ready ? @agent : @error_outcome
      end
    end

    def on_ready(&block)
      return self unless block

      callback_agent = nil
      @mutex.synchronize do
        if @status == :ready
          callback_agent = @agent
        elsif @status == :pending
          @ready_callbacks << block
        end
      end
      block.call(callback_agent) if callback_agent
      self
    end

    def on_error(&block)
      return self unless block

      callback_outcome = nil
      @mutex.synchronize do
        if @status == :error
          callback_outcome = @error_outcome
        elsif @status == :pending
          @error_callbacks << block
        end
      end
      block.call(callback_outcome) if callback_outcome
      self
    end

    def _resolve(agent:)
      callbacks = nil
      @mutex.synchronize do
        return if @status != :pending

        @status = :ready
        @agent = agent
        callbacks = @ready_callbacks.dup
        @ready_callbacks.clear
        @error_callbacks.clear
        @condition.broadcast
      end
      callbacks.each { |callback| callback.call(agent) }
    end

    def _reject(outcome:)
      callbacks = nil
      @mutex.synchronize do
        return if @status != :pending

        @status = :error
        @error_outcome = outcome
        callbacks = @error_callbacks.dup
        @ready_callbacks.clear
        @error_callbacks.clear
        @condition.broadcast
      end
      callbacks.each { |callback| callback.call(outcome) }
    end
  end
end
