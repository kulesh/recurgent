#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/recurgent"

MODEL = Agent::DEFAULT_MODEL

puts "=== HTTP Client ==="
puts "Model: #{MODEL}"
puts
puts "No HTTP gem. No curl wrapper. No REST client."
puts "Just a name and a URL. The LLM figures out the rest."
puts

http = Agent.for("HTTP client", model: MODEL)

puts "-> http.get('https://httpbin.org/get')"
puts http.get("https://httpbin.org/get")
puts

puts "-> http.status('https://httpbin.org/status/418')"
puts http.status("https://httpbin.org/status/418")
puts

puts "-> http.headers('https://httpbin.org/response-headers?X-Custom=hello')"
puts http.headers("https://httpbin.org/response-headers?X-Custom=hello").inspect
puts

puts "-> http.post('https://httpbin.org/post', body: '{\"key\": \"value\"}')"
puts http.post("https://httpbin.org/post", body: '{"key": "value"}')
