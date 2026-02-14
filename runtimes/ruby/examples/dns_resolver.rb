#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/recurgent"

MODEL = Agent::DEFAULT_MODEL

puts "=== DNS Resolver ==="
puts "Model: #{MODEL}"
puts
puts "No dig. No nslookup. No DNS library."
puts "Just a name. The LLM figures out the rest."
puts

dns = Agent.for("DNS resolver", model: MODEL)

puts "-> dns.resolve('example.com')"
puts dns.resolve("example.com").inspect
puts

puts "-> dns.mx_records('google.com')"
puts dns.mx_records("google.com").inspect
puts

puts "-> dns.reverse_lookup('8.8.8.8')"
puts dns.reverse_lookup("8.8.8.8")
puts

puts "-> dns.nameservers('github.com')"
puts dns.nameservers("github.com").inspect
