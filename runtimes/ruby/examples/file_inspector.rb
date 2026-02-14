#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/recurgent"

MODEL = Agent::DEFAULT_MODEL
FILE = File.expand_path("../lib/recurgent.rb", __dir__)

puts "=== File Inspector ==="
puts "Model: #{MODEL}"
puts "File:  #{FILE}"
puts
puts "No file-reading tool. No grep. No wc."
puts "Just a name and a path. The LLM figures out the rest."
puts

inspector = Agent.for(
  "text file inspector for #{FILE}",
  model: MODEL
)

puts "-> inspector.load"
inspector.load
puts

puts "-> inspector.line_count"
puts inspector.line_count
puts

puts "-> inspector.word_count"
puts inspector.word_count
puts

puts "-> inspector.find('method_missing')"
puts inspector.find("method_missing").inspect
puts

puts "-> inspector.longest_line"
puts inspector.longest_line.inspect
puts

puts "-> inspector.blank_lines"
puts inspector.blank_lines
