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
      Fast::Gains.consolidate!

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
      Fast::Gains.consolidate!

      expect(File.exist?(temp_file)).to be true
      data = JSON.parse(File.read(temp_file)).last
      expect(data['command']).to eq('mcp:ruby_class_source')
      expect(data['bytes_searched']).to eq(File.size(test_file))
    end
  end

  describe 'SQL tracking' do
    let(:server) { Fast::McpServer.new }

    it 'records gains for search_sql_ast' do
      test_file = File.join(temp_dir, 'sample.sql')
      File.write(test_file, 'SELECT * FROM users;')

      params = {
        'name' => 'search_sql_ast',
        'arguments' => {
          'pattern' => '(select_stmt ...)',
          'paths' => [test_file]
        }
      }
      
      allow(server).to receive(:write_response)

      server.send(:handle_tool_call, '1', params)
      Fast::Gains.consolidate!

      expect(File.exist?(temp_file)).to be true
      data = JSON.parse(File.read(temp_file)).last
      expect(data['command']).to eq('mcp:search_sql_ast')
      expect(data['bytes_searched']).to eq(File.size(test_file))
    end

    it 'processes rewrite_sql without file touching' do
      params = {
        'name' => 'rewrite_sql',
        'arguments' => {
          'pattern' => '(relname "users")',
          'source' => 'SELECT 1 FROM users;',
          'replacement' => '"clients"'
        }
      }

      allow(server).to receive(:write_response) do |id, response|
        expect(response[:content].first[:text]).to include('SELECT 1 FROM \"clients\";')
      end

      server.send(:handle_tool_call, '1', params)
    end

    it 'records gains for rewrite_sql_file and builds diff' do
      test_file = File.join(temp_dir, 'sample.sql')
      content = "SELECT 1 FROM users;\n"
      File.write(test_file, content)

      params = {
        'name' => 'rewrite_sql_file',
        'arguments' => {
          'pattern' => '(relname "users")',
          'file' => test_file,
          'replacement' => '"clients"'
        }
      }
      
      allow(server).to receive(:write_response) do |id, response|
        json = JSON.parse(response[:content].first[:text])
        expect(json['changed']).to be true
        expect(json['diff'].first['after']).to eq('SELECT 1 FROM "clients";')
      end

      server.send(:handle_tool_call, '1', params)
      Fast::Gains.consolidate!

      data = JSON.parse(File.read(temp_file)).last
      expect(data['command']).to eq('mcp:rewrite_sql_file')
      expect(data['bytes_searched']).to eq(content.size)
      expect(File.read(test_file)).to eq("SELECT 1 FROM \"clients\";\n")
    end
  end
end
