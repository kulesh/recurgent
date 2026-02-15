# frozen_string_literal: true

require "spec_helper"

RSpec.describe Agent::PreparationTicket do
  it "resolves to ready and returns the prepared agent" do
    ticket = described_class.new
    agent = Agent.for("calculator", log: false)

    ticket._resolve(agent: agent)

    expect(ticket.status).to eq(:ready)
    expect(ticket.agent).to eq(agent)
    expect(ticket.await).to eq(agent)
  end

  it "rejects to error and returns outcome from await" do
    ticket = described_class.new
    outcome = Agent::Outcome.error(
      error_type: "environment_preparing",
      error_message: "failed",
      retriable: true,
      tool_role: "tool_builder",
      method_name: "prepare"
    )

    ticket._reject(outcome: outcome)

    expect(ticket.status).to eq(:error)
    expect(ticket.await).to eq(outcome)
  end

  it "runs ready callback when resolved" do
    ticket = described_class.new
    agent = Agent.for("calculator", log: false)
    received = nil
    ticket.on_ready { |prepared| received = prepared }

    ticket._resolve(agent: agent)

    expect(received).to eq(agent)
  end

  it "runs error callback when rejected" do
    ticket = described_class.new
    outcome = Agent::Outcome.error(
      error_type: "environment_preparing",
      error_message: "failed",
      retriable: true,
      tool_role: "tool_builder",
      method_name: "prepare"
    )
    received = nil
    ticket.on_error { |error_outcome| received = error_outcome }

    ticket._reject(outcome: outcome)

    expect(received).to eq(outcome)
  end

  it "returns nil when await times out while pending" do
    ticket = described_class.new

    expect(ticket.await(timeout: 0.01)).to be_nil
    expect(ticket.status).to eq(:pending)
  end
end
