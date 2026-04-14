# frozen_string_literal: true

require 'spec_helper'
require 'fast/mcp_server'
require 'fileutils'
require 'json'

RSpec.describe Fast::McpServer do
  let(:server) { Fast::McpServer.new }
  let(:temp_dir) { File.expand_path('tmp_mcp_pagination', Dir.pwd) }
  let(:test_file) { File.join(temp_dir, 'sample.rb') }

  before do
    FileUtils.mkdir_p(temp_dir)
    File.write(test_file, <<~RUBY)
      def first; end
      def second; end
      def third; end
    RUBY
    allow(server).to receive(:write_response)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe 'pagination' do
    it 'returns paginated results for search_ruby_ast' do
      params = {
        'name' => 'search_ruby_ast',
        'arguments' => {
          'pattern' => '(def ...)',
          'paths' => [test_file],
          'limit' => 2
        }
      }

      expect(server).to receive(:write_response) do |_id, response|
        content = JSON.parse(response[:content].first[:text])
        expect(content['matches'].size).to eq(2)
        expect(content['total']).to eq(3)
        expect(content['offset']).to eq(0)
        expect(content['limit']).to eq(2)
        expect(content['has_more']).to be true
        expect(content['matches'][0]['code']).to include('def first')
        expect(content['matches'][1]['code']).to include('def second')
      end

      server.send(:handle_tool_call, '1', params)
    end

    it 'handles offset for search_ruby_ast' do
      params = {
        'name' => 'search_ruby_ast',
        'arguments' => {
          'pattern' => '(def ...)',
          'paths' => [test_file],
          'offset' => 2,
          'limit' => 2
        }
      }

      expect(server).to receive(:write_response) do |_id, response|
        content = JSON.parse(response[:content].first[:text])
        expect(content['matches'].size).to eq(1)
        expect(content['total']).to eq(3)
        expect(content['offset']).to eq(2)
        expect(content['limit']).to eq(2)
        expect(content['has_more']).to be false
        expect(content['matches'][0]['code']).to include('def third')
      end

      server.send(:handle_tool_call, '1', params)
    end

    it 'returns paginated results for ruby_method_source' do
      params = {
        'name' => 'ruby_method_source',
        'arguments' => {
          'method_name' => '...',
          'paths' => [test_file],
          'limit' => 1
        }
      }

      expect(server).to receive(:write_response) do |_id, response|
        content = JSON.parse(response[:content].first[:text])
        expect(content['matches'].size).to eq(1)
        expect(content['total']).to eq(3)
        expect(content['has_more']).to be true
      end

      server.send(:handle_tool_call, '1', params)
    end

    it 'returns paginated results for ruby_class_source' do
      class_file = File.join(temp_dir, 'classes.rb')
      File.write(class_file, <<~RUBY)
        class A; end
        class A; end
      RUBY
      params = {
        'name' => 'ruby_class_source',
        'arguments' => {
          'class_name' => 'A',
          'paths' => [class_file],
          'limit' => 1
        }
      }

      expect(server).to receive(:write_response) do |_id, response|
        content = JSON.parse(response[:content].first[:text])
        expect(content['matches'].size).to eq(1)
        expect(content['total']).to eq(2)
        expect(content['has_more']).to be true
      end

      server.send(:handle_tool_call, '1', params)
    end
  end
end
