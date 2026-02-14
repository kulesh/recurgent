#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/recurgent"

MODEL = Agent::DEFAULT_MODEL
ROOT = File.expand_path("..", __dir__)

puts "=== Filesystem Explorer ==="
puts "Model: #{MODEL}"
puts "Root:  #{ROOT}"
puts
puts "No Dir.glob. No File.read. No Find.find."
puts "Just a directory and an LLM. Navigate like a tree."
puts

fs = Agent.for("directory explorer at #{ROOT}", model: MODEL)

puts "-> fs.list"
entries = fs.list
puts entries
puts

puts "-> fs.cd('lib')"
lib = fs.cd("lib")
puts lib
puts

puts "-> lib.list"
lib_files = lib.list
puts lib_files
puts

puts "-> lib.find('recurgent.rb')"
main = lib.find("recurgent.rb")
puts main
puts

if main.is_a?(Agent)
  puts "-> main.line_count"
  puts main.line_count
  puts

  puts "-> main.grep('def ')"
  puts main.grep("def ").inspect
end
