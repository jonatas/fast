# frozen_string_literal: true

require 'json'
require 'stringio'
require 'fast'
require 'fast/version'
require 'fast/cli'
require 'fast/sql'

module Fast
  # Implements the Model Context Protocol (MCP) server over STDIO.
  class McpServer
    TOOLS = [
      {
        name: 'validate_fast_pattern',
        description: 'Validate a Fast AST pattern. Returns true if valid, or a specific syntax error message if invalid.',
        inputSchema: {
          type: 'object',
          properties: {
            pattern: { type: 'string', description: 'Fast AST pattern to validate.' }
          },
          required: ['pattern']
        }
      },
      {
        name: 'search_ruby_ast',
        description: 'Search Ruby files using a Fast AST pattern. Returns file, line range, and source. Use show_ast=true only when you need the s-expression.',
        inputSchema: {
          type: 'object',
          properties: {
            pattern: { type: 'string', description: 'Fast AST pattern, e.g. "(def match?)" or "(send nil :raise ...)".' },
            paths:   { type: 'array', items: { type: 'string' }, description: 'Files or directories to search.' },
            show_ast: { type: 'boolean', description: 'Include s-expression AST in results (default: false).' },
            offset:   { type: 'integer', description: 'Offset for pagination (default: 0).' },
            limit:    { type: 'integer', description: 'Maximum number of results to return (default: 20).' }
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
            show_ast:    { type: 'boolean', description: 'Include s-expression AST in results (default: false).' },
            offset:      { type: 'integer', description: 'Offset for pagination (default: 0).' },
            limit:       { type: 'integer', description: 'Maximum number of results to return (default: 20).' }
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
            show_ast:   { type: 'boolean', description: 'Include s-expression AST in results (default: false).' },
            offset:     { type: 'integer', description: 'Offset for pagination (default: 0).' },
            limit:      { type: 'integer', description: 'Maximum number of results to return (default: 20).' }
          },
          required: ['class_name', 'paths']
        }
      },
      {
        name: 'code_to_pattern',
        description: 'Convert a Ruby code snippet into Fast search patterns. Use this to author search patterns ' \
                     'from example code: "exact_pattern" is the AST s-expression and matches the exact code shape, ' \
                     '"generalized_pattern" replaces names and literals with wildcards to find similar code.',
        inputSchema: {
          type: 'object',
          properties: {
            source: { type: 'string', description: 'Ruby code snippet, e.g. "user.save!" or "def foo; end".' }
          },
          required: ['source']
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
            policy: { type: 'string', description: 'Shell command returning exit status 0 on success. Uses {file} for the temporary file created during the rewrite round. Example: `bin/spring rspec --fail-fast {file}`' },
            strategy: { type: 'string', enum: ['combinations', 'apply_individual_survivors', 'dry_run'], description: 'Strategy for the experiment (default: combinations).' },
            cwd: { type: 'string', description: 'Optional directory to run the policy command in.' },
            env: { type: 'object', additionalProperties: { type: 'string' }, description: 'Optional environment variables for the policy command.' },
            gains_dir: { type: 'string', description: 'Optional directory to store gains files.' },
            gains_enabled: { type: 'boolean', description: 'Enable or disable gains tracking for this tool call (default: true).' }
          },
          required: ['name', 'lookup', 'search', 'edit', 'policy']
        }
      },
      {
        name: 'search_sql_ast',
        description: 'Search SQL files using a Fast AST pattern. Returns file, line range, and source.',
        inputSchema: {
          type: 'object',
          properties: {
            pattern: { type: 'string', description: 'Fast AST pattern for SQL, e.g. "(select_stmt ...)" or "(relname \"users\")".' },
            paths:   { type: 'array', items: { type: 'string' }, description: 'Files or directories to search.' },
            show_ast: { type: 'boolean', description: 'Include s-expression AST in results (default: false).' },
            offset:   { type: 'integer', description: 'Offset for pagination (default: 0).' },
            limit:    { type: 'integer', description: 'Maximum number of results to return (default: 20).' }
          },
          required: ['pattern', 'paths']
        }
      },
      {
        name: 'rewrite_sql',
        description: 'Apply a Fast pattern replacement to SQL source code. Returns the rewritten source. Does NOT write to disk.',
        inputSchema: {
          type: 'object',
          properties: {
            source:      { type: 'string', description: 'SQL source code to rewrite.' },
            pattern:     { type: 'string', description: 'Fast AST pattern to match nodes for replacement.' },
            replacement: { type: 'string', description: 'SQL expression or value to replace matched node source with.' }
          },
          required: ['source', 'pattern', 'replacement']
        }
      },
      {
        name: 'rewrite_sql_file',
        description: 'Apply a Fast pattern replacement to a SQL file in-place. Returns lines changed and a diff.',
        inputSchema: {
          type: 'object',
          properties: {
            file:        { type: 'string', description: 'Path to the SQL file to rewrite.' },
            pattern:     { type: 'string', description: 'Fast AST pattern to match nodes for replacement.' },
            replacement: { type: 'string', description: 'SQL expression or value to replace matched node source with.' }
          },
          required: ['file', 'pattern', 'replacement']
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
      offset    = args['offset'] || 0
      limit     = args['limit'] || 20

      if args['gains_enabled'] == false
        Fast.disable_gain_track!
      else
        Fast.enable_gain_track!
      end
      Fast.gains_dir = args['gains_dir'] if args['gains_dir']

      @gains = Gains.new("mcp:#{tool_name}")

      if args['pattern'] && !args['pattern'].start_with?('(', '{', '[', '/') && !args['pattern'].match?(/^[a-z_]+$/)
        raise "Invalid Fast AST pattern: '#{args['pattern']}'. Did you mean to use an s-expression like '(#{args['pattern']})'?"
      end

      result =
        case tool_name
        when 'validate_fast_pattern'
          execute_validate_pattern(args['pattern'])
        when 'search_ruby_ast'
          execute_search(args['pattern'], args['paths'], show_ast: show_ast, offset: offset, limit: limit)
        when 'ruby_method_source'
          execute_method_search(args['method_name'], args['paths'],
                                class_name: args['class_name'], show_ast: show_ast, offset: offset, limit: limit)
        when 'ruby_class_source'
          execute_class_search(args['class_name'], args['paths'], show_ast: show_ast, offset: offset, limit: limit)
        when 'code_to_pattern'
          execute_code_to_pattern(args['source'])
        when 'rewrite_ruby'
          execute_rewrite(args['source'], args['pattern'], args['replacement'])
        when 'rewrite_ruby_file'
          execute_rewrite_file(args['file'], args['pattern'], args['replacement'])
        when 'run_fast_experiment'
          execute_fast_experiment(args)
        when 'search_sql_ast'
          execute_sql_search(args['pattern'], args['paths'], show_ast: show_ast, offset: offset, limit: limit)
        when 'rewrite_sql'
          execute_sql_rewrite(args['source'], args['pattern'], args['replacement'])
        when 'rewrite_sql_file'
          execute_sql_rewrite_file(args['file'], args['pattern'], args['replacement'])
        else
          raise "Unknown tool: #{tool_name}"
        end

      if result.is_a?(Hash) && result[:matches]
        result[:matches].each do |match|
          @gains.record_report(match[:code]) if match[:code]
        end
      else
        @gains.record_report(result.to_json)
      end
      @gains.save!
      write_response(id, { content: [{ type: 'text', text: JSON.generate(result) }] })
    rescue => e
      write_error(id, -32603, "Tool execution failed: #{e.message}", e.backtrace.join("\n"))
    end

    def execute_validate_pattern(pattern)
      res = Fast.expression(pattern)
      { valid: true, structure: expression_structure(res) }
    rescue StandardError => e
      { valid: false, error: e.message }
    end

    # Serialize a parsed expression tree, descending into nested expressions
    def expression_structure(exp)
      case exp
      when Array then exp.map { |e| expression_structure(e) }
      else exp.respond_to?(:to_h) ? exp.to_h : exp
      end
    end

    def execute_search(pattern, paths, show_ast: false, offset: nil, limit: nil)
      # Parse upfront: per-file graceful degradation would swallow a syntax
      # error and report zero matches instead of failing the tool call.
      Fast.expression(pattern)

      results = []
      files_searched = 0
      on_result = ->(file, matches) do
        @gains&.record_match(file) if matches.any?
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
      on_search = ->(file) { files_searched += 1; @gains&.record_search(file) }

      Fast.search_all(pattern, paths, parallel: false, on_result: on_result, on_search: on_search)

      matches = if offset || limit
                  results[offset || 0, limit || results.size] || []
                else
                  results
                end

      result = {
        matches:  matches,
        total:    results.size,
        offset:   offset,
        limit:    limit,
        has_more: (offset || 0) + (limit || results.size) < results.size
      }
      result[:hint] = zero_result_hint(paths, files_searched, zero_match_hint(pattern)) if results.empty?
      result
    end

    def execute_method_search(method_name, paths, class_name: nil, show_ast: false, offset: nil, limit: nil)
      pattern = method_pattern(method_name)
      results = []
      files_searched = 0
      on_result = ->(file, matches) do
        @gains&.record_match(file) if matches.any?
        matches.compact.each do |node|
          next unless (exp = node_expression(node))
          next if class_name && !class_defined_in_file?(class_name, file)

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
      on_search = ->(file) { files_searched += 1; @gains&.record_search(file) }

      Fast.search_all(pattern, paths, parallel: false, on_result: on_result, on_search: on_search)

      matches = if offset || limit
                  results[offset || 0, limit || results.size] || []
                else
                  results
                end

      result = {
        matches:  matches,
        total:    results.size,
        offset:   offset,
        limit:    limit,
        has_more: (offset || 0) + (limit || results.size) < results.size
      }
      if results.empty?
        fallback = "No instance (def) or singleton (defs) method named '#{method_name}' found. " \
                   'It may be defined dynamically (attr_accessor, define_method, delegate) — try ' \
                   "search_ruby_ast with (send nil :define_method (sym :#{method_name}))."
        result[:hint] = zero_result_hint(paths, files_searched, fallback)
      end
      result
    end

    def execute_class_search(class_name, paths, show_ast: false, offset: nil, limit: nil)
      results = []
      files_searched = 0
      on_result = ->(file, matches) do
        @gains&.record_match(file) if matches.any?
        matches.compact.each do |node|
          next unless %i[class module].include?(node.type)
          next unless node.children.first&.children&.last&.to_s == class_name.split('::').last
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
      on_search = ->(file) { files_searched += 1; @gains&.record_search(file) }
      Fast.search_all(class_pattern(class_name), paths, parallel: false, on_result: on_result, on_search: on_search)
      
      matches = if offset || limit
                  results[offset || 0, limit || results.size] || []
                else
                  results
                end

      result = {
        matches:  matches,
        total:    results.size,
        offset:   offset,
        limit:    limit,
        has_more: (offset || 0) + (limit || results.size) < results.size
      }
      if results.empty?
        fallback = "No class or module named '#{class_name}' found. " \
                   'Names are matched by the last constant segment (e.g. "Bar" finds Foo::Bar).'
        result[:hint] = zero_result_hint(paths, files_searched, fallback)
      end
      result
    end

    def execute_code_to_pattern(source)
      ast = Fast.ast(source)
      raise "Could not parse Ruby source: #{source.inspect}" unless ast

      {
        exact_pattern: ast.to_sexp,
        generalized_pattern: Fast.expression_from(ast)
      }
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

      @gains&.record_search(file)
      original = File.read(file)
      rewritten = Fast.replace_file(pattern, file) do |node|
        @gains&.record_match(file)
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

    def execute_fast_experiment(args)
      name = args['name']
      lookup_path = args['lookup']
      search_pattern = args['search']
      edit_code = args['edit']
      policy_command = args['policy']
      cwd = args['cwd']
      env = args['env'] || {}

      require 'fast/experiment'
      original_stdout = $stdout.dup
      capture_output = StringIO.new
      $stdout = capture_output

      results = []
      begin
        experiment = Fast.experiment(name) do
          lookup lookup_path
          search search_pattern
          strategy args['strategy'].to_sym if args['strategy']
          edit do |node, *captures|
            eval(edit_code)
          end
          policy do |new_file|
            cmd = policy_command.gsub('{file}', new_file)
            system(env, cmd, chdir: cwd || Dir.pwd)
          end
        end
        experiment.files.each { |f| @gains&.record_search(f) }
        results = experiment.run
      ensure
        $stdout = original_stdout
      end

      # Exclude any color from captured output
      log = capture_output.string.gsub(/\e\[([;\d]+)?m/, '')
      
      { experiment: name, log: log, results: results }
    end

    # Matches a bare capitalized token used as a send/csend receiver, e.g. (send Fast :version)
    BARE_CONST_RECEIVER = /\((?:send|csend)\s+([A-Z]\w*)/.freeze

    # An empty result caused by wrong paths must not read like "the code does not exist"
    def zero_result_hint(paths, files_searched, fallback)
      missing = paths.reject { |path| File.exist?(path) }
      if missing.any?
        "Paths do not exist: #{missing.inspect} — searches resolve from #{Dir.pwd}."
      elsif files_searched.zero?
        "No Ruby files found under #{paths.inspect} — check the paths argument."
      else
        fallback
      end
    end

    # Guidance returned alongside empty search results so agents can correct
    # a wrong pattern instead of concluding the code does not exist.
    def zero_match_hint(pattern)
      if (match = BARE_CONST_RECEIVER.match(pattern))
        name = match[1]
        "No matches. '#{name}' is a bare token but constants are nodes — try (const nil :#{name}), " \
          "e.g. (send (const nil :#{name}) ...). Use code_to_pattern with sample code to see the exact AST shape."
      else
        'No matches. The pattern may not reflect the real AST shape — use code_to_pattern with a ' \
          'snippet you expect to match, and validate_fast_pattern to check syntax.'
      end
    end

    def execute_sql_search(pattern, paths, show_ast: false, offset: nil, limit: nil)
      results = []
      on_result = ->(file, matches) do
        @gains&.record_match(file) if matches.any?
        matches.compact.each do |node|
          next unless (exp = node_expression(node))

          entry = {
            file:       file,
            line_start: exp.line,
            line_end:   exp.last_line,
            code:       exp.source
          }
          entry[:ast] = Fast.highlight(node, show_sexp: true, colorize: false) if show_ast
          results << entry
        end
      end
      on_search = ->(file) { @gains&.record_search(file) }

      Fast.search_all(pattern, paths, parallel: false, on_result: on_result, on_search: on_search, files_from: :sql_files_from)
      
      matches = if offset || limit
                  results[offset || 0, limit || results.size] || []
                else
                  results
                end

      {
        matches:  matches,
        total:    results.size,
        offset:   offset,
        limit:    limit,
        has_more: (offset || 0) + (limit || results.size) < results.size
      }
    end

    def execute_sql_rewrite(source, pattern, replacement)
      ast    = Fast.parse_sql(source)
      result = Fast.replace_sql(pattern, ast) do |node|
        replace(node.loc.expression, replacement)
      end
      { original: source, rewritten: result, changed: result != source }
    end

    def execute_sql_rewrite_file(file, pattern, replacement)
      raise "File not found: #{file}" unless File.exist?(file)

      @gains&.record_search(file)
      original = File.read(file)
      rewritten = Fast.replace_sql_file(pattern, file) do |node|
        @gains&.record_match(file)
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

    # Returns loc.expression if available
    def node_expression(node)
      return unless node.respond_to?(:loc) && node.loc.respond_to?(:expression)

      node.loc.expression
    end

    # Matches both instance methods (def) and singleton methods (defs, e.g. def self.x).
    # Operator and bracket method names (==, [], <<) are not plain pattern tokens,
    # so they are matched through an anchored regex literal instead.
    def method_pattern(method_name)
      if method_name.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*[!?=]?\z/)
        "{(def #{method_name}) (defs _ #{method_name})}"
      elsif method_name.include?('/') || method_name.match?(/\s/)
        raise "Unsupported method name: #{method_name.inspect}"
      else
        escaped = Regexp.escape(method_name)
        "{(def /^#{escaped}$/) (defs _ /^#{escaped}$/)}"
      end
    end

    # Anchors the class or module name in the search pattern itself: Fast.search
    # stops descending once a node matches, so a bare {class module} pattern would
    # return an enclosing module and never reach a class nested inside it.
    def class_pattern(class_name)
      last_segment = class_name.split('::').last
      "{(class (const {nil _} #{last_segment})) (module (const {nil _} #{last_segment}))}"
    end

    # Check whether a class or module is defined anywhere in the file's AST
    def class_defined_in_file?(class_name, file)
      Fast.search_file(class_pattern(class_name), file).any?
    rescue StandardError
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
