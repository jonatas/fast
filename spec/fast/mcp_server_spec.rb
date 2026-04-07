# frozen_string_literal: true

require 'spec_helper'
require 'fast/mcp_server'
require 'fileutils'
require 'json'

RSpec.describe Fast::McpServer do
  let(:temp_dir) { File.join(Dir.pwd, 'tmp_mcp_gains') }
  let(:temp_file) { File.join(temp_dir, 'gains.json') }

  before do
    stub_const('Fast::Gains::STORAGE_DIR', temp_dir)
    stub_const('Fast::Gains::STORAGE_FILE', temp_file)
    FileUtils.mkdir_p(temp_dir)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe 'gains tracking' do
    let(:server) { Fast::McpServer.new }

    it 'records gains for search_ruby_ast' do
      test_file = File.join(temp_dir, 'sample.rb')
      File.write(test_file, 'def hello; end')

      params = {
        'name' => 'search_ruby_ast',
        'arguments' => {
          'pattern' => '(def hello)',
          'paths' => [test_file]
        }
      }
      
      # Mock write_response to avoid STDOUT pollution
      allow(server).to receive(:write_response)

      server.send(:handle_tool_call, '1', params)

      expect(File.exist?(temp_file)).to be true
      data = JSON.parse(File.read(temp_file)).last
      expect(data['command']).to eq('mcp:search_ruby_ast')
      expect(data['bytes_searched']).to eq(File.size(test_file))
      expect(data['bytes_reported']).to be > 0
    end

    it 'records gains for ruby_class_source' do
      test_file = File.join(temp_dir, 'sample.rb')
      File.write(test_file, 'class Hello; end')

      params = {
        'name' => 'ruby_class_source',
        'arguments' => {
          'class_name' => 'Hello',
          'paths' => [test_file]
        }
      }
      
      allow(server).to receive(:write_response)

      server.send(:handle_tool_call, '1', params)

      expect(File.exist?(temp_file)).to be true
      data = JSON.parse(File.read(temp_file)).last
      expect(data['command']).to eq('mcp:ruby_class_source')
      expect(data['bytes_searched']).to eq(File.size(test_file))
    end
  end
end
