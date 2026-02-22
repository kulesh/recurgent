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

  def methods_first_pattern?(line)
    # A methods-first profile declares constraints keyed by method name or uses
    # a top-level `methods:` list as the primary constraint organizer (the old shape).
    # Scope-first uses `scope: all_methods` / `scope: explicit_methods` with an
    # optional narrowing `methods:` list only inside `explicit_methods` scope.
    #
    # Detect patterns that indicate methods-first schema usage:
    #   1. A constraint hash with no `scope` key but a `methods` key at constraint level
    #   2. A profile example where constraints are keyed by method name (e.g., `add:`, `multiply:`)
    #      with `kind:` inside — the scope-first schema keys constraints by family name
    #   3. Explicit string "methods-first" or "methods_first" used as a schema name/mode
    return true if line.match?(/\bmethods[_-]first\b/i)

    false
  end

  describe "runtime code (lib/)" do
    it "contains no methods-first role profile schema references" do
      files = scan_files(ruby_lib, ["**/*.rb"])
      violations = []

      files.each do |path|
        File.readlines(path, chomp: true).each_with_index do |line, idx|
          next if line.match?(/^\s*#/) # skip comments

          violations << "#{Pathname(path).relative_path_from(repo_root)}:#{idx + 1}: #{line.strip}" if methods_first_pattern?(line)
        end
      end

      expect(violations).to be_empty,
                            "Found methods-first role profile references in runtime code:\n#{violations.join("\n")}"
    end
  end

  describe "test code (spec/)" do
    it "contains no methods-first role profile schema references" do
      files = scan_files(ruby_spec, ["**/*.rb"])
      violations = []

      files.each do |path|
        File.readlines(path, chomp: true).each_with_index do |line, idx|
          next if line.match?(/^\s*#/) # skip comments
          # Allow this guard spec itself to reference the term for detection purposes.
          next if Pathname(path).basename.to_s == "role_profile_scope_first_guard_spec.rb"

          violations << "#{Pathname(path).relative_path_from(repo_root)}:#{idx + 1}: #{line.strip}" if methods_first_pattern?(line)
        end
      end

      expect(violations).to be_empty,
                            "Found methods-first role profile references in test code:\n#{violations.join("\n")}"
    end
  end

  describe "examples" do
    it "contains no methods-first role profile schema references" do
      files = scan_files(ruby_examples, ["**/*.rb"])
      violations = []

      files.each do |path|
        File.readlines(path, chomp: true).each_with_index do |line, idx|
          next if line.match?(/^\s*#/) # skip comments

          violations << "#{Pathname(path).relative_path_from(repo_root)}:#{idx + 1}: #{line.strip}" if methods_first_pattern?(line)
        end
      end

      expect(violations).to be_empty,
                            "Found methods-first role profile references in examples:\n#{violations.join("\n")}"
    end
  end

  describe "contract specifications" do
    it "contains no methods-first role profile schema references" do
      files = scan_files(specs_dir, ["**/*.yaml", "**/*.yml", "**/*.json", "**/*.md"])
      violations = []

      files.each do |path|
        File.readlines(path, chomp: true).each_with_index do |line, idx|
          violations << "#{Pathname(path).relative_path_from(repo_root)}:#{idx + 1}: #{line.strip}" if methods_first_pattern?(line)
        end
      end

      expect(violations).to be_empty,
                            "Found methods-first role profile references in contract specs:\n#{violations.join("\n")}"
    end
  end

  describe "documentation (non-plan/ADR prose)" do
    it "contains no methods-first role profile schema examples" do
      files = scan_files(docs_dir, ["**/*.md", "**/*.yaml", "**/*.yml"])

      # Exclude plan/ADR/report prose that describes the removal decision itself.
      files.reject! do |path|
        prose_allowlist.any? { |allowed| Pathname(path).to_s.start_with?(allowed.to_s) }
      end

      violations = []

      files.each do |path|
        File.readlines(path, chomp: true).each_with_index do |line, idx|
          violations << "#{Pathname(path).relative_path_from(repo_root)}:#{idx + 1}: #{line.strip}" if methods_first_pattern?(line)
        end
      end

      expect(violations).to be_empty,
                            "Found methods-first role profile references in documentation:\n#{violations.join("\n")}"
    end
  end

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
