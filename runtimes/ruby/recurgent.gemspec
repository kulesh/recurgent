# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "recurgent"
  spec.version = "0.1.0"
  spec.summary = "Inside-out LLM tool calling for Ruby."
  spec.description = "LLM-powered objects that intercept all method calls, " \
                     "ask an LLM what Ruby code to execute, then eval the response."
  spec.authors = ["Kulesh Shanmugasundaram"]
  spec.homepage = "https://github.com/kulesh/actuator"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/kulesh/actuator"
  spec.metadata["changelog_uri"] = "https://github.com/kulesh/actuator/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/kulesh/actuator/blob/main/README.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/kulesh/actuator/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "anthropic", "~> 1.0"
  spec.add_dependency "base64" # required by anthropic on Ruby >= 3.4

  # Optional: gem "openai" for OpenAI model support (gpt-*, o1-*, o3-*, o4-*, chatgpt-*)
  # Install with: gem install openai
end
