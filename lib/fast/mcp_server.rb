# frozen_string_literal: true

require 'json'
require 'stringio'
require 'fast'
require 'fast/version'
require 'fast/cli'

module Fast
  # Implements the Model Context Protocol (MCP) server over STDIO.
  class McpServer
    TOOLS = [
      {
        name: 'search_ruby_ast',
        description: 'Search Ruby files using a Fast AST pattern. Returns file, line range, and source. Use show_ast=true only when you need the s-expression.',
        inputSchema: {
          type: 'object',
          properties: {
            pattern: { type: 'string', description: 'Fast AST pattern, e.g. "(def match?)" or "(send nil :raise ...)".' },
            paths:   { type: 'array', items: { type: 'string' }, description: 'Files or directories to search.' },
            show_ast: { type: 'boolean', description: 'Include s-expression AST in results (default: false).' }
          },
          required: ['pattern', 'paths']
        }
      },
      {
        name: 'ruby_method_source',
        description: 'Extract source of a Ruby method by name across files. Optionally filter by class name.',
        inputSchema: {
          type: 'object',
          properties: {
            method_name: { type: 'string', description: 'Method name, e.g. "initialize".' },
            paths:       { type: 'array', items: { type: 'string' }, description: 'Files or directories to search.' },
            class_name:  { type: 'string', description: 'Optional class name to restrict results, e.g. "Matcher".' },
            show_ast:    { type: 'boolean', description: 'Include s-expression AST in results (default: false).' }
          },
          required: ['method_name', 'paths']
        }
      },
      {
        name: 'ruby_class_source',
        description: 'Extract the full source of a Ruby class by name.',
        inputSchema: {
          type: 'object',
          properties: {
            class_name: { type: 'string', description: 'Class name to extract, e.g. "Rewriter".' },
            paths:      { type: 'array', items: { type: 'string' }, description: 'Files or directories to search.' },
            show_ast:   { type: 'boolean', description: 'Include s-expression AST in results (default: false).' }
          },
          required: ['class_name', 'paths']
        }
      },
      {
        name: 'rewrite_ruby',
        description: 'Apply a Fast pattern replacement to Ruby source code. Returns the rewritten source. Does NOT write to disk.',
        inputSchema: {
          type: 'object',
          properties: {
            source:      { type: 'string', description: 'Ruby source code to rewrite.' },
            pattern:     { type: 'string', description: 'Fast AST pattern to match nodes for replacement.' },
            replacement: { type: 'string', description: 'Ruby expression to replace matched node source with.' }
          },
          required: ['source', 'pattern', 'replacement']
        }
      },
      {
        name: 'rewrite_ruby_file',
        description: 'Apply a Fast pattern replacement to a Ruby file in-place. Returns lines changed and a diff. Use rewrite_ruby first to preview.',
        inputSchema: {
          type: 'object',
          properties: {
            file:        { type: 'string', description: 'Path to the Ruby file to rewrite.' },
            pattern:     { type: 'string', description: 'Fast AST pattern to match nodes for replacement.' },
            replacement: { type: 'string', description: 'Ruby expression to replace matched node source with.' }
          },
          required: ['file', 'pattern', 'replacement']
        }
      },
      {
        name: 'run_fast_experiment',
        description: 'Propose and execute a Fast experiment to safely refactor code. The experiment is validated against a policy command (e.g. tests) and only successful rewrites are applied. Always use {file} in the policy command to refer to the modified test file.',
        inputSchema: {
          type: 'object',
          properties: {
            name: { type: 'string', description: 'Name of the experiment, e.g. "RSpec/UseBuildStubbed"' },
            lookup: { type: 'string', description: 'Folder or file to target, e.g. "spec"' },
            search: { type: 'string', description: 'Fast AST search pattern to find nodes.' },
            edit: { type: 'string', description: 'Ruby code to evaluate in Rewriter context. Has access to `node` variable. Example: `replace(node.loc.expression, "build_stubbed")`' },
            policy: { type: 'string', description: 'Shell command returning exit status 0 on success. Uses {file} for the temporary file created during the rewrite round. Example: `bin/spring rspec --fail-fast {file}`' }
          },
          required: ['name', 'lookup', 'search', 'edit', 'policy']
        }
      }
    ].freeze


    def self.run!
      new.run
    end

    def run
      STDOUT.sync = true

      while (line = STDIN.gets)
        line = line.strip
        next if line.empty?

        begin
          request = JSON.parse(line)
          handle_request(request)
        rescue JSON::ParserError => e
          write_error(nil, -32700, 'Parse error', e.message)
        rescue StandardError => e
          write_error(request&.fetch('id', nil), -32603, 'Internal error', e.message)
        end
      end
    end

    private

    def handle_request(request)
      id     = request['id']
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
        write_response(id, { tools: TOOLS })
      when 'tools/call'
        handle_tool_call(id, params)
      when 'notifications/initialized'
        nil
      else
        write_error(id, -32601, 'Method not found', "#{method} not supported") if id
      end
    end

    def handle_tool_call(id, params)
      tool_name = params['name']
      args      = params['arguments'] || {}
      show_ast  = args['show_ast'] || false

      result =
        case tool_name
        when 'search_ruby_ast'
          execute_search(args['pattern'], args['paths'], show_ast: show_ast)
        when 'ruby_method_source'
          execute_method_search(args['method_name'], args['paths'],
                                class_name: args['class_name'], show_ast: show_ast)
        when 'ruby_class_source'
          execute_class_search(args['class_name'], args['paths'], show_ast: show_ast)
        when 'rewrite_ruby'
          execute_rewrite(args['source'], args['pattern'], args['replacement'])
        when 'rewrite_ruby_file'
          execute_rewrite_file(args['file'], args['pattern'], args['replacement'])
        when 'run_fast_experiment'
          execute_fast_experiment(args['name'], args['lookup'], args['search'], args['edit'], args['policy'])
        else
          raise "Unknown tool: #{tool_name}"
        end

      write_response(id, { content: [{ type: 'text', text: JSON.generate(result) }] })
    rescue => e
      write_error(id, -32603, 'Tool execution failed', e.message)
    end

    def execute_search(pattern, paths, show_ast: false)
      results = []
      on_result = ->(file, matches) do
        matches.compact.each do |node|
          next unless (exp = node_expression(node))

          entry = {
            file:       file,
            line_start: exp.line,
            line_end:   exp.last_line,
            code:       Fast.highlight(node, colorize: false)
          }
          entry[:ast] = Fast.highlight(node, show_sexp: true, colorize: false) if show_ast
          results << entry
        end
      end

      Fast.search_all(pattern, paths, parallel: false, on_result: on_result)
      results
    end

    def execute_method_search(method_name, paths, class_name: nil, show_ast: false)
      pattern = "(def #{method_name})"
      results = execute_search(pattern, paths, show_ast: show_ast)
      return results unless class_name

      # Filter: keep only methods whose file contains the class
      results.select do |r|
        class_defined_in_file?(class_name, r[:file])
      end
    end

    def execute_class_search(class_name, paths, show_ast: false)
      # Use simple (class ...) pattern then filter by name — avoids nil/superclass edge cases
      results = []
      on_result = ->(file, matches) do
        matches.compact.each do |node|
          next unless node.type == :class
          next unless node.children.first&.children&.last&.to_s == class_name
          next unless (exp = node_expression(node))

          entry = {
            file:       file,
            line_start: exp.line,
            line_end:   exp.last_line,
            code:       Fast.highlight(node, colorize: false)
          }
          entry[:ast] = Fast.highlight(node, show_sexp: true, colorize: false) if show_ast
          results << entry
        end
      end
      Fast.search_all('(class ...)', paths, parallel: false, on_result: on_result)
      results.select { |r| r[:file] } # already filtered above
    end

    def execute_rewrite(source, pattern, replacement)
      ast    = Fast.ast(source)
      result = Fast.replace(pattern, ast, source) do |node|
        replace(node.loc.expression, replacement)
      end
      { original: source, rewritten: result, changed: result != source }
    end

    def execute_rewrite_file(file, pattern, replacement)
      raise "File not found: #{file}" unless File.exist?(file)

      original = File.read(file)
      rewritten = Fast.replace_file(pattern, file) do |node|
        replace(node.loc.expression, replacement)
      end

      return { file: file, changed: false } if rewritten.nil? || rewritten == original

      # Build a compact line-level diff
      orig_lines     = original.lines
      rewritten_lines = rewritten.lines
      diff = orig_lines.each_with_index.filter_map do |line, i|
        new_line = rewritten_lines[i]
        next if line == new_line

        { line: i + 1, before: line.rstrip, after: (new_line&.rstrip || '') }
      end

      File.write(file, rewritten)
      { file: file, changed: true, diff: diff }
    end

    def execute_fast_experiment(name, lookup_path, search_pattern, edit_code, policy_command)
      require 'fast/experiment'
      original_stdout = $stdout.dup
      capture_output = StringIO.new
      $stdout = capture_output

      begin
        experiment = Fast.experiment(name) do
          lookup lookup_path
          search search_pattern
          edit do |node, *captures|
            eval(edit_code)
          end
          policy do |new_file|
            cmd = policy_command.gsub('{file}', new_file)
            system(cmd)
          end
        end
        experiment.run
      ensure
        $stdout = original_stdout
      end

      # Exclude any color from captured output
      log = capture_output.string.gsub(/\e\[([;\d]+)?m/, '')
      
      { experiment: name, log: log }
    end

    # Returns loc.expression if available
    def node_expression(node)
      return unless node.respond_to?(:loc) && node.loc.respond_to?(:expression)

      node.loc.expression
    end

    # Check whether a class is defined anywhere in the file's AST
    def class_defined_in_file?(class_name, file)
      Fast.search_file('(class ...)', file).any? do |node|
        node.children.first&.children&.last&.to_s == class_name
      end
    rescue
      false
    end

    def write_response(id, result)
      STDOUT.puts({ jsonrpc: '2.0', id: id, result: result }.to_json)
    end

    def write_error(id, code, message, data = nil)
      err      = { code: code, message: message }
      err[:data] = data if data
      response = { jsonrpc: '2.0', error: err }
      response[:id] = id if id
      STDOUT.puts response.to_json
    end
  end
end
