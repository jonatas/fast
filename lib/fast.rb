# frozen_string_literal: true

require 'fileutils'
require 'rubocop-ast'
require_relative 'fast/rewriter'

# suppress output to avoid parser gem warnings'
def suppress_output
  original_stdout = $stdout.clone
  original_stderr = $stderr.clone
  $stderr.reopen File.new('/dev/null', 'w')
  $stdout.reopen File.new('/dev/null', 'w')
  yield
ensure
  $stdout.reopen original_stdout
  $stderr.reopen original_stderr
end

suppress_output do
  require 'parser'
  require 'parser/current'
end

RuboCop::AST::NodePattern.class_eval do
  alias_method :match?, :match
end
# Fast is a tool to help you search in the code through the Abstract Syntax Tree
module Fast
  class << self
    # @return [Astrolabe::Node] from the parsed content
    # @example
    #   Fast.ast("1") # => s(:int, 1)
    #   Fast.ast("a.b") # => s(:send, s(:send, nil, :a), :b)
    def ast(content, buffer_name: '(string)')
      buffer = Parser::Source::Buffer.new(buffer_name)
      buffer.source = content
      Parser::CurrentRuby.new(RuboCop::AST::Builder.new).parse(buffer)
    end

    # @return [Astrolabe::Node] parsed from file content
    # caches the content based on the filename.
    # @example
    #   Fast.ast_from_file("example.rb") # => s(...)
    def ast_from_file(file)
      @cache ||= {}
      @cache[file] ||= ast(IO.read(file), buffer_name: file)
    end

    # Verify if a given AST matches with a specific pattern
    # @return [Boolean] case matches ast with the current expression
    # @example
    #   Fast.match?("int", Fast.ast("1")) # => true
    def match?(pattern, ast, *args)
      expression(pattern).match(ast, *args)
    end

    # Search with pattern directly on file
    # @return [Array<Astrolabe::Node>] that matches the pattern
    def search_file(pattern, file)
      node = ast_from_file(file)
      return [] unless node

      search pattern, node
    end

    # Search with pattern on a directory or multiple files
    # @param [String] pattern
    # @param [Array<String>] *locations where to search. Default is '.'
    # @return [Hash<String,Array<Astrolabe::Node>>] with files and results
    def search_all(pattern, locations = ['.'], parallel: true, on_result: nil)
      group_results(build_grouped_search(:search_file, pattern, on_result),
                    locations, parallel: parallel)
    end

    # Capture with pattern on a directory or multiple files
    # @param [String] pattern
    # @param [Array<String>] locations where to search. Default is '.'
    # @return [Hash<String,Object>] with files and captures
    def capture_all(pattern, locations = ['.'], parallel: true, on_result: nil)
      group_results(build_grouped_search(:capture_file, pattern, on_result),
                    locations, parallel: parallel)
    end

    # @return [Proc] binding `pattern` argument from a given `method_name`.
    # @param [Symbol] method_name with `:capture_file` or `:search_file`
    # @param [String] pattern to match in a search to any file
    # @param [Proc] on_result is a callback that can be notified soon it matches
    def build_grouped_search(method_name, pattern, on_result)
      search_pattern = method(method_name).curry.call(pattern)
      proc do |file|
        results = search_pattern.call(file)
        next if results.nil? || results.empty?

        on_result&.(file, results)
        { file => results }
      end
    end

    # Compact grouped results by file allowing parallel processing.
    # @param [Proc] group_files allows to define a search that can be executed
    # parallel or not.
    # @param [Proc] on_result allows to define a callback for fast feedback
    # while it process several locations in parallel.
    # @param [Boolean] parallel runs the `group_files` in parallel
    # @return [Hash[String, Array]] with files and results
    def group_results(group_files, locations, parallel: true)
      files = ruby_files_from(*locations)
      if parallel
        require 'parallel' unless defined?(Parallel)
        Parallel.map(files, &group_files)
      else
        files.map(&group_files)
      end.compact.inject(&:merge!)
    end

    # Capture elements from searches in files. Keep in mind you need to use `$`
    # in the pattern to make it work.
    # @return [Array<Object>] captured from the pattern matched in the file
    def capture_file(pattern, file)
      node = ast_from_file(file)
      return [] unless node

      capture pattern, node
    end

    # Search recursively into a node and its children.
    # If the node matches with the pattern it returns the node,
    # otherwise it recursively collect possible children nodes
    # @yield node and capture if block given
    def search(pattern, node, *args)
      if (match = match?(pattern, node, *args))
        yield node, match if block_given?
        match != true ? [node, match] : [node]
      else
        node.each_child_node
          .flat_map { |child| search(pattern, child, *args) }
          .compact.flatten
      end
    end

    # Only captures from a search
    # @return [Array<Object>] with all captured elements.
    def capture(pattern, node)
      if (match = match?(pattern, node))
        match == true ? node : match
      else
        node.each_child_node
          .flat_map { |child| capture(pattern, child) }
          .compact.flatten
      end
    end

    def expression(string)
      RuboCop::AST::NodePattern.new(string)
    end

    # @return [Array<String>] with all ruby files from arguments.
    # @param files can be file paths or directories.
    # When the argument is a folder, it recursively fetches all `.rb` files from it.
    def ruby_files_from(*files)
      dir_filter = File.method(:directory?)
      directories = files.select(&dir_filter)

      if directories.any?
        files -= directories
        files |= directories.flat_map { |dir| Dir["#{dir}/**/*.rb"] }
        files.uniq!
      end
      files.reject(&dir_filter)
    end

    # Extracts a node pattern expression from a given node supressing identifiers and primitive types.
    # Useful to index abstract patterns or similar code structure.
    # @see https://jonatas.github.io/fast/similarity_tutorial/
    # @return [String] with an pattern to search from it.
    # @param node [Astrolabe::Node]
    # @example
    #   Fast.expression_from(Fast.ast('1')) # => '(int _)'
    #   Fast.expression_from(Fast.ast('a = 1')) # => '(lvasgn _ (int _))'
    #   Fast.expression_from(Fast.ast('def name; person.name end')) # => '(def _ (args) (send (send nil _) _))'
    def expression_from(node)
      case node
      when Parser::AST::Node
        children_expression = node.children.map(&method(:expression_from)).join(' ')
        "(#{node.type}#{' ' + children_expression if node.children.any?})"
      when nil, 'nil'
        'nil?'
      when Symbol, String, Numeric
        '_'
      end
    end
  end
end
