# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Agent::WorkerExecutor do
  let(:env_dir) { Dir.mktmpdir("recurgent-worker-env-") }
  let(:executor) { described_class.new }

  before do
    File.write(File.join(env_dir, "Gemfile"), "source \"https://rubygems.org\"\n")
  end

  after do
    executor.shutdown
    FileUtils.rm_rf(env_dir)
  end

  it "executes a request and returns value plus context snapshot" do
    executor.start(env_dir: env_dir)
    response = executor.execute(
      payload: {
        method_name: "add",
        code: "context[:count] = context.fetch(:count, 0) + 1; result = args[0] + kwargs[:extra]",
        args: [2],
        kwargs: { extra: 3 },
        context_snapshot: {}
      },
      timeout_seconds: 5
    )

    expect(response["status"]).to eq("ok")
    expect(response["value"]).to eq(5)
    expect(response["context_snapshot"]).to include("count" => 1)
  end

  it "returns non_serializable_result when worker value cannot cross JSON boundary" do
    executor.start(env_dir: env_dir)
    response = executor.execute(
      payload: {
        method_name: "bad_value",
        code: "result = Object.new",
        args: [],
        kwargs: {},
        context_snapshot: {}
      },
      timeout_seconds: 5
    )

    expect(response["status"]).to eq("error")
    expect(response["error_type"]).to eq("non_serializable_result")
  end

  it "raises WorkerTimeout when the worker does not respond in time" do
    executor.start(env_dir: env_dir)
    expect do
      executor.execute(
        payload: {
          method_name: "slow",
          code: "sleep 0.1; result = 1",
          args: [],
          kwargs: {},
          context_snapshot: {}
        },
        timeout_seconds: 0.01
      )
    end.to raise_error(Agent::WorkerExecutor::WorkerTimeout)
  end
end
