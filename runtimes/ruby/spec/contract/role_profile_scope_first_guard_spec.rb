# frozen_string_literal: true

require "pathname"

RSpec.describe "ADR 0024 scope-first role profile guard" do
  let(:repo_root) { Pathname(__dir__).join("../../../../").expand_path }
  let(:ruby_lib) { repo_root.join("runtimes/ruby/lib") }
  let(:ruby_spec) { repo_root.join("runtimes/ruby/spec") }
  let(:ruby_examples) { repo_root.join("runtimes/ruby/examples") }
  let(:docs_dir) { repo_root.join("docs") }
  let(:specs_dir) { repo_root.join("specs") }

  # Directories that contain plan/ADR prose describing the removal decision itself.
  # References to "methods-first" in these files are historical rationale, not schema examples.
  let(:prose_allowlist) do
    [
      repo_root.join("docs/plans"),
      repo_root.join("docs/adrs"),
      repo_root.join("docs/reports")
    ]
  end

  def scan_files(root, globs)
    globs.flat_map { |glob| Dir[root.join(glob).to_s] }
         .select { |path| File.file?(path) }
  end

  def methods_first_terminology?(line)
    # Terminology guard: catches the literal term "methods-first" or "methods_first"
    # appearing in code, docs, or examples. This prevents reintroduction of the old
    # schema *concept* in prose and naming (variable names, comments describing the
    # old approach as current, doc examples teaching the old pattern).
    #
    # Structural enforcement of the scope-first contract is handled separately by
    # RoleProfile.normalize, which rejects invalid scope/methods combinations at
    # the API level. See the "RoleProfile.normalize scope-first enforcement" group.
    line.match?(/\bmethods[_-]first\b/i)
  end

  # Layer 1: Terminology guard.
  # Prevents the "methods-first" term from reappearing in active code, tests,
  # examples, contracts, or documentation (plan/ADR/report prose is allowlisted
  # since it describes the removal decision itself).
  describe "terminology guard: no methods-first references outside historical prose" do
    it "runtime code (lib/) does not reference the methods-first term" do
      files = scan_files(ruby_lib, ["**/*.rb"])
      violations = []

      files.each do |path|
        File.readlines(path, chomp: true).each_with_index do |line, idx|
          next if line.match?(/^\s*#/) # skip comments

          violations << "#{Pathname(path).relative_path_from(repo_root)}:#{idx + 1}: #{line.strip}" if methods_first_terminology?(line)
        end
      end

      expect(violations).to be_empty,
                            "Found methods-first role profile references in runtime code:\n#{violations.join("\n")}"
    end

    it "test code (spec/) does not reference the methods-first term" do
      files = scan_files(ruby_spec, ["**/*.rb"])
      violations = []

      files.each do |path|
        File.readlines(path, chomp: true).each_with_index do |line, idx|
          next if line.match?(/^\s*#/) # skip comments
          # Allow this guard spec itself to reference the term for detection purposes.
          next if Pathname(path).basename.to_s == "role_profile_scope_first_guard_spec.rb"

          violations << "#{Pathname(path).relative_path_from(repo_root)}:#{idx + 1}: #{line.strip}" if methods_first_terminology?(line)
        end
      end

      expect(violations).to be_empty,
                            "Found methods-first role profile references in test code:\n#{violations.join("\n")}"
    end

    it "examples do not reference the methods-first term" do
      files = scan_files(ruby_examples, ["**/*.rb"])
      violations = []

      files.each do |path|
        File.readlines(path, chomp: true).each_with_index do |line, idx|
          next if line.match?(/^\s*#/) # skip comments

          violations << "#{Pathname(path).relative_path_from(repo_root)}:#{idx + 1}: #{line.strip}" if methods_first_terminology?(line)
        end
      end

      expect(violations).to be_empty,
                            "Found methods-first role profile references in examples:\n#{violations.join("\n")}"
    end

    it "contract specifications do not reference the methods-first term" do
      files = scan_files(specs_dir, ["**/*.yaml", "**/*.yml", "**/*.json", "**/*.md"])
      violations = []

      files.each do |path|
        File.readlines(path, chomp: true).each_with_index do |line, idx|
          violations << "#{Pathname(path).relative_path_from(repo_root)}:#{idx + 1}: #{line.strip}" if methods_first_terminology?(line)
        end
      end

      expect(violations).to be_empty,
                            "Found methods-first role profile references in contract specs:\n#{violations.join("\n")}"
    end

    it "documentation (excluding plan/ADR/report prose) does not reference the methods-first term" do
      files = scan_files(docs_dir, ["**/*.md", "**/*.yaml", "**/*.yml"])

      # Exclude plan/ADR/report prose that describes the removal decision itself.
      files.reject! do |path|
        prose_allowlist.any? { |allowed| Pathname(path).to_s.start_with?(allowed.to_s) }
      end

      violations = []

      files.each do |path|
        File.readlines(path, chomp: true).each_with_index do |line, idx|
          violations << "#{Pathname(path).relative_path_from(repo_root)}:#{idx + 1}: #{line.strip}" if methods_first_terminology?(line)
        end
      end

      expect(violations).to be_empty,
                            "Found methods-first role profile references in documentation:\n#{violations.join("\n")}"
    end
  end

  # Layer 2: Structural enforcement.
  # RoleProfile.normalize is the runtime gate that rejects methods-first shapes.
  # These tests verify the API contract: scope defaults to all_methods, methods
  # lists are forbidden under all_methods scope, and required under explicit_methods.
  describe "RoleProfile.normalize scope-first enforcement" do
    it "rejects constraints with methods list under all_methods scope" do
      input = {
        role: "calculator",
        version: 1,
        constraints: {
          accumulator_slot: {
            kind: :shared_state_slot,
            scope: :all_methods,
            methods: %w[add subtract]
          }
        }
      }

      expect { Agent::RoleProfile.normalize(input) }.to raise_error(ArgumentError, /must not declare methods/)
    end

    it "requires methods list under explicit_methods scope" do
      input = {
        role: "calculator",
        version: 1,
        constraints: {
          accumulator_slot: {
            kind: :shared_state_slot,
            scope: :explicit_methods
          }
        }
      }

      expect { Agent::RoleProfile.normalize(input) }.to raise_error(ArgumentError, /requires methods for scope explicit_methods/)
    end

    it "defaults scope to all_methods when omitted" do
      input = {
        role: "calculator",
        version: 1,
        constraints: {
          accumulator_slot: { kind: :shared_state_slot }
        }
      }

      profile = Agent::RoleProfile.normalize(input)
      expect(profile[:constraints][:accumulator_slot][:scope]).to eq(:all_methods)
    end

    it "accepts scope-first constraint with exclude_methods" do
      input = {
        role: "calculator",
        version: 1,
        constraints: {
          arithmetic_shape: {
            kind: :return_shape_family,
            scope: :all_methods,
            exclude_methods: %w[history]
          }
        }
      }

      profile = Agent::RoleProfile.normalize(input)
      expect(profile[:constraints][:arithmetic_shape][:exclude_methods]).to eq(%w[history])
    end

    it "accepts explicit_methods scope with required methods list" do
      input = {
        role: "calculator",
        version: 1,
        constraints: {
          arithmetic_shape: {
            kind: :return_shape_family,
            scope: :explicit_methods,
            methods: %w[add subtract multiply]
          }
        }
      }

      profile = Agent::RoleProfile.normalize(input)
      expect(profile[:constraints][:arithmetic_shape][:methods]).to eq(%w[add subtract multiply])
      expect(profile[:constraints][:arithmetic_shape][:scope]).to eq(:explicit_methods)
    end
  end
end
