# frozen_string_literal: true

require "spec_helper"

RSpec.describe Agent::WorkerSupervisor do
  let(:executor) { instance_double(Agent::WorkerExecutor) }
  let(:factory) { -> { executor } }
  let(:supervisor) { described_class.new(executor_factory: factory, max_restarts: 1) }
  let(:payload) { { method_name: "m", code: "result = 1", args: [], kwargs: {}, context_snapshot: {} } }

  before do
    allow(executor).to receive(:start).and_return(executor)
    allow(executor).to receive(:shutdown)
    allow(executor).to receive(:alive?).and_return(true)
    allow(executor).to receive(:pid).and_return(1234)
  end

  after do
    supervisor.shutdown
  end

  it "reuses worker for the same environment id" do
    allow(executor).to receive(:execute).and_return({ "status" => "ok", "value" => 1, "context_snapshot" => {} })

    first = supervisor.execute(env_id: "env-a", env_dir: "/tmp/a", payload: payload, timeout_seconds: 1)
    second = supervisor.execute(env_id: "env-a", env_dir: "/tmp/a", payload: payload, timeout_seconds: 1)

    expect(first[:status]).to eq("ok")
    expect(second[:status]).to eq("ok")
    expect(executor).to have_received(:start).once
  end

  it "restarts worker when env id changes" do
    allow(executor).to receive(:execute).and_return({ "status" => "ok", "value" => 1, "context_snapshot" => {} })

    supervisor.execute(env_id: "env-a", env_dir: "/tmp/a", payload: payload, timeout_seconds: 1)
    supervisor.execute(env_id: "env-b", env_dir: "/tmp/b", payload: payload, timeout_seconds: 1)

    expect(executor).to have_received(:shutdown).once
    expect(executor).to have_received(:start).twice
  end

  it "maps executor timeout to timeout error payload" do
    allow(executor).to receive(:execute).and_raise(Agent::WorkerExecutor::WorkerTimeout, "timed out")

    response = supervisor.execute(env_id: "env-a", env_dir: "/tmp/a", payload: payload, timeout_seconds: 1)

    expect(response[:status]).to eq("error")
    expect(response[:error_type]).to eq("timeout")
  end

  it "maps executor crashes to worker_crash payload" do
    allow(executor).to receive(:execute).and_raise(Agent::WorkerExecutor::WorkerExited, "worker died")

    response = supervisor.execute(env_id: "env-a", env_dir: "/tmp/a", payload: payload, timeout_seconds: 1)

    expect(response[:status]).to eq("error")
    expect(response[:error_type]).to eq("worker_crash")
  end
end
