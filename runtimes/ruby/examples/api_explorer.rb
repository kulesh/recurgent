#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/recurgent"

MODEL = Agent::DEFAULT_MODEL
BASE_URL = "https://jsonplaceholder.typicode.com"

puts "=== REST API Explorer ==="
puts "Model: #{MODEL}"
puts "API:   #{BASE_URL}"
puts
puts "No REST client. No JSON parser. No response classes."
puts "Just a URL and an LLM. Drill into the API like a filesystem."
puts

api = Agent.for("REST API explorer for #{BASE_URL}", model: MODEL)

# Each step drills deeper. The LLM may wrap results in Agent objects,
# so we can keep calling methods on whatever comes back. Guard with exit
# since the LLM might return a plain value at any level.

puts "-> api.users"
users = api.users
puts users
puts
exit unless users.is_a?(Agent)

puts "-> users.count"
puts users.count
puts

puts "-> users.find(name: 'Leanne Graham')"
user = users.find(name: "Leanne Graham")
puts user
puts
exit unless user.is_a?(Agent)

puts "-> user.posts"
posts = user.posts
puts posts
puts
exit unless posts.is_a?(Agent)

puts "-> posts.first"
first_post = posts.first
puts first_post
puts
exit unless first_post.is_a?(Agent)

puts "-> first_post.comments"
comments = first_post.comments
puts comments
puts
exit unless comments.is_a?(Agent)

puts "-> comments.count"
puts comments.count
