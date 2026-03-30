# frozen_string_literal: true

require 'open3'
require 'json'

def send_request(stdin, method, params, id: 1)
  req = { jsonrpc: "2.0", id: id, method: method, params: params }
  stdin.puts(req.to_json)
end

def read_response(stdout)
  line = stdout.gets
  JSON.parse(line) if line
end

Open3.popen3("bin/fast-mcp") do |stdin, stdout, stderr, wait_thr|
  puts "1. Testing initialize..."
  send_request(stdin, "initialize", {}, id: 1)
  resp = read_response(stdout)
  puts "Resp: #{resp.inspect}\n\n"

  puts "2. Testing tools/list..."
  send_request(stdin, "tools/list", {}, id: 2)
  resp = read_response(stdout)
  puts "Tools: #{resp['result']['tools'].map { |t| t['name'] }}\n\n"

  puts "3. Testing ruby_method_source (valid)..."
  send_request(stdin, "tools/call", { name: "ruby_method_source", arguments: { method_name: "match?", paths: ["lib/fast.rb"] } }, id: 3)
  resp = read_response(stdout)
  content = JSON.parse(resp['result']['content'][0]['text']) rescue resp
  puts "Found #{content.size if content.is_a?(Array)} matches for match? in fast.rb\n\n"

  puts "4. Testing search_ruby_ast (invalid pattern syntax)..."
  send_request(stdin, "tools/call", { name: "search_ruby_ast", arguments: { pattern: "(def unclosed", paths: ["lib"] } }, id: 4)
  resp = read_response(stdout)
  puts "Resp: #{resp.inspect}\n\n"

  puts "5. Testing search_ruby_ast (non-existent path)..."
  send_request(stdin, "tools/call", { name: "search_ruby_ast", arguments: { pattern: "(def match?)", paths: ["does_not_exist"] } }, id: 5)
  resp = read_response(stdout)
  puts "Resp: #{resp.inspect}\n\n"
end
