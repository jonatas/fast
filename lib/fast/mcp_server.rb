# frozen_string_literal: true

require 'json'
require 'fast'
require 'fast/version'
require 'fast/cli'

module Fast
  # Implements the Model Context Protocol (MCP) server over STDIO.
  class McpServer
    def self.run!
      new.run
    end

    def run
      # Disable STDOUT buffering for instantaneous JSON-RPC replies
      STDOUT.sync = true

      while (line = STDIN.gets)
        line = line.strip
        next if line.empty?

        begin
          request = JSON.parse(line)
          handle_request(request)
        rescue JSON::ParserError => e
          write_error(nil, -32700, "Parse error", e.message)
        rescue StandardError => e
          write_error(request&.fetch('id', nil), -32603, "Internal error", e.message)
        end
      end
    end

    private

    def handle_request(request)
      id = request['id']
      method = request['method']
      params = request['params'] || {}

      case method
      when 'initialize'
        write_response(id, {
          protocolVersion: '2024-11-05',
          capabilities: { tools: {} },
          serverInfo: { name: 'fast-mcp', version: Fast::VERSION }
        })
      when 'tools/list'
        write_response(id, {
          tools: [
            {
              name: 'search_ruby_ast',
              description: 'Searches a Ruby codebase (via AST) using a Fast pattern.',
              inputSchema: {
                type: 'object',
                properties: {
                  pattern: { type: 'string', description: 'The Fast AST pattern to search (e.g., "(def match?)").' },
                  paths: { type: 'array', items: { type: 'string' }, description: 'List of files or directories to search.' }
                },
                required: ['pattern', 'paths']
              }
            },
            {
              name: 'ruby_method_source',
              description: 'Extracts the source code of a specific Ruby method by name.',
              inputSchema: {
                type: 'object',
                properties: {
                  method_name: { type: 'string', description: 'Name of the method to extract (e.g., "initialize").' },
                  paths: { type: 'array', items: { type: 'string' }, description: 'List of files or directories to search.' }
                },
                required: ['method_name', 'paths']
              }
            }
          ]
        })
      when 'tools/call'
        handle_tool_call(id, params)
      when 'notifications/initialized'
        # Just acknowledge
      else
        write_error(id, -32601, "Method not found", "Method #{method} not supported") if id
      end
    end

    def handle_tool_call(id, params)
      tool_name = params['name']
      args = params['arguments'] || {}

      begin
        result =
          case tool_name
          when 'search_ruby_ast'
            execute_search(args['pattern'], args['paths'])
          when 'ruby_method_source'
            execute_search("(def #{args['method_name']})", args['paths'])
          else
            raise "Unknown tool: #{tool_name}"
          end

        write_response(id, {
          content: [
            {
              type: 'text',
              text: JSON.generate(result)
            }
          ]
        })
      rescue => e
        write_error(id, -32603, "Tool execution failed", e.message)
      end
    end

    def execute_search(pattern, paths)
      results = []
      on_result = ->(file, matches) do
        matches.compact.each do |node|
          next unless node.respond_to?(:loc) && node.loc.respond_to?(:expression)
          
          exp = node.loc.expression
          next unless exp # Sometimes AST nodes missing expression

          results << {
            file: file,
            line_start: exp.line,
            line_end: exp.last_line,
            code: Fast.highlight(node, colorize: false),
            ast: Fast.highlight(node, show_sexp: true, colorize: false)
          }
        end
      end
      
      Fast.search_all(pattern, paths, parallel: false, on_result: on_result)
      results
    end

    def write_response(id, result)
      response = { jsonrpc: '2.0', id: id, result: result }
      STDOUT.puts response.to_json
    end

    def write_error(id, code, message, data = nil)
      err = { code: code, message: message }
      err[:data] = data if data
      response = { jsonrpc: '2.0', error: err }
      response[:id] = id if id
      STDOUT.puts response.to_json
    end
  end
end
