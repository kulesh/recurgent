#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/recurgent"

MODEL = "gpt-5.2-codex"
FILE = File.expand_path("data/sales_2024.csv", __dir__)

puts "=== CSV Explorer ==="
puts "Model: #{MODEL}"
puts "File:  #{FILE}"
puts
puts "No CSV library. No date parser. No charting gem."
puts "Just a name and a file path. The LLM figures out the rest."
puts

csv = Agent.for(
  "CSV data analyst for #{FILE} — the file has messy dates (mixed formats), missing values, and notes",
  model: MODEL
)

puts "-> csv.load"
csv.load
puts

puts "-> csv.row_count"
puts csv.row_count
puts

puts "-> csv.column_names"
puts csv.column_names.inspect
puts

puts "-> csv.total_revenue"
puts csv.total_revenue
puts

puts "-> csv.top_sellers(n: 3)"
puts csv.top_sellers(n: 3).inspect
puts

puts "-> csv.revenue_by_category"
puts csv.revenue_by_category.inspect
puts

puts "-> csv.revenue_by_quarter"
puts csv.revenue_by_quarter.inspect
puts

puts "-> csv.data_quality_report"
puts csv.data_quality_report.inspect
