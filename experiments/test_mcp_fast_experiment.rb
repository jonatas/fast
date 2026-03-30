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

# We want to use a dummy file to safely run our experiment on!
File.write("dummy_spec.rb", <<~RUBY)
  describe "my dummy spec" do
    let(:user) { create(:user) }
  end
RUBY

Open3.popen3("bin/fast-mcp") do |stdin, stdout, stderr, wait_thr|
  puts "Testing run_fast_experiment..."
  
  # As policy just use a dummy true that doesn't actually run rspec so we test the algorithm
  # We will just verify if the file was touched or if the AST rule worked.
  send_request(stdin, "tools/call", {
    name: "run_fast_experiment", 
    arguments: { 
      name: "RSpec/DummyUseBuildStubbed",
      lookup: "dummy_spec.rb",
      search: "(send nil create)",
      edit: "replace(node.loc.selector, 'build_stubbed')",
      policy: "true # {file}"
    } 
  }, id: 1)

  resp = read_response(stdout)
  puts "Response from server:"
  puts JSON.pretty_generate(resp)

  puts "\nContent of dummy_spec.rb after experiment:"
  puts File.read("dummy_spec.rb")
end

File.delete("dummy_spec.rb")
