# frozen_string_literal: true

require "open3"
require "rbconfig"
require "spec_helper"

RSpec.describe "observability demo example" do
  it "runs successfully and reports an ok outcome" do
    script_path = File.expand_path("../examples/observability_demo.rb", __dir__)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, script_path)

    expect(status.success?).to eq(true), "demo failed with stderr: #{stderr}"
    expect(stdout).to include("Outcome status: ok")
  end
end
