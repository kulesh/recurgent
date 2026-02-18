# frozen_string_literal: true

RSpec.shared_context "agent spec context" do
  let(:mock_provider) { instance_double(Agent::Providers::Anthropic) }
  let(:runtime_toolstore_root) { Dir.mktmpdir("recurgent-spec-toolstore-") }

  before do
    allow(Agent::Providers::Anthropic).to receive(:new).and_return(mock_provider)
    allow(Agent).to receive(:default_log_path).and_return(false)
    Agent.reset_runtime_config!
    Agent.configure_runtime(toolstore_root: runtime_toolstore_root)
  end

  after do
    FileUtils.rm_rf(runtime_toolstore_root)
    Agent.reset_runtime_config!
  end

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
