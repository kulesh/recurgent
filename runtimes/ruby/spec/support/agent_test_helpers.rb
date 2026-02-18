# frozen_string_literal: true

require "tmpdir"
require "timeout"

# Shared setup for Agent specs decomposed from recurgent_spec.rb.
# Included via RSpec.configure in spec_helper.rb.
module AgentTestHelpers
  def program_payload(code:, dependencies: nil)
    payload = { code: code }
    payload[:dependencies] = dependencies unless dependencies.nil?
    payload
  end

  def stub_llm_response(code, dependencies: nil)
    allow(mock_provider).to receive(:generate_program).and_return(
      program_payload(code: code, dependencies: dependencies)
    )
  end

  def expect_llm_call_with(code:, dependencies: nil, **matchers)
    expect(mock_provider)
      .to receive(:generate_program)
      .with(hash_including(**matchers))
      .and_return(program_payload(code: code, dependencies: dependencies))
  end

  def expect_ok_outcome(outcome, value:)
    expect(outcome).to be_a(Agent::Outcome)
    expect(outcome).to be_ok
    expect(outcome.value).to eq(value)
  end

  def expect_error_outcome(outcome, type:, retriable:)
    expect(outcome).to be_a(Agent::Outcome)
    expect(outcome).to be_error
    expect(outcome.error_type).to eq(type)
    expect(outcome.retriable).to eq(retriable)
    expect(outcome.error_message).not_to be_nil
  end
end

RSpec.configure do |config|
  config.include AgentTestHelpers, :agent_test_helpers
end
