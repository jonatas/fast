# frozen_string_literal: true

require 'fileutils'

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

# Fast is a tool to help you search in the code through the Abstract Syntax Tree
module Fast
  # Literals are shortcuts allowed inside {ExpressionParser}
  LITERAL = {
    '...' => ->(node) { node&.children&.any? },
    '_' => ->(node) { !node.nil? },
    'nil' => nil
  }.freeze

  # Allowed tokens in the node pattern domain
  TOKENIZER = %r/
    [\+\-\/\*\\!]         # operators or negation
    |
    ===?                  # == or ===
    |
    \d+\.\d*              # decimals and floats
    |
    "[^"]+"               # strings
    |
    _                     # something not nil: match
    |
    \.{3}                 # a node with children: ...
    |
    \[|\]                 # square brackets `[` and `]` for all
    |
    \^                    # node has children with
    |
    \?                    # maybe expression
    |
    [\d\w_]+[=\\!\?]?     # method names or numbers
    |
    \(|\)                 # parens `(` and `)` for tuples
    |
    \{|\}                 # curly brackets `{` and `}` for any
    |
    \$                    # capture
    |
    \#\w[\d\w_]+[\\!\?]?  # custom method call
    |
    \.\w[\d\w_]+\?       # instance method call
    |
    \\\d                  # find using captured expression
    |
    %\d                   # bind extra arguments to the expression
  /x.freeze

  # Set some convention methods from file.
class Node < Parser::AST::Node
  attr_accessor :parent

  # @return [String] with path of the file or simply buffer name.
  def buffer_name
    @buffer_name || expression.source_buffer.name
  end

  def assign_properties(properties)
    if properties
      @parent = properties[:parent]
      @buffer_name = properties[:buffer_name]
    end
  end

  # @return [Parser::Source::Range] from the expression
  def expression
    location.expression
  end

  # @return [String] with the content of the #expression
  def source
    expression.source
  end

  # @return [Boolean] true if a file exists with the #buffer_name
  def from_file?
    File.exist?(buffer_name)
  end

  # @return [Array<String>] with authors from the current expression range
  def blame_authors
    `git blame -L #{expression.first_line},#{expression.last_line} #{buffer_name}`.lines.map do |line|
      line.split('(')[1].split(/\d+/).first.strip
    end
  end

  # @return [String] with the first element from #blame_authors
  def author
    blame_authors.first
  end

  # Search recursively into a node and its children using a pattern.
  # @param [String] pattern
  # @param [Array] *args extra arguments to interpolate in the pattern.
  # @return [Array<Fast::Node>>] with files and results
  def search(pattern, *args)
    Fast.search(pattern, self, *args)
  end

  # Captures elements from search recursively
  # @param [String] pattern
  # @param [Array] *args extra arguments to interpolate in the pattern.
  # @return [Array<Fast::Node>>] with files and results
  def capture(pattern, *args)
    Fast.capture(pattern, self, *args)
  end

  def each_child_node(&block)
    return to_enum(__method__) unless block_given?
    children.each do |child|
      if child.is_a?(::Parser::AST::Node)
        yield child
      end
    end
  end

  def root?
    parent.nil?
  end

  def method_missing(method_name, *args, &block)
    if method_name.to_s.end_with?("_type?")
      return type == method_name.to_s.chomp("_type?").to_sym
    end
    super
  end

  def each_descendant(*types, &block)
    return to_enum(__method__, *types) unless block_given?

    children.each do |child|
      if child.is_a?(::Parser::AST::Node)
        yield child if types.empty? || types.include?(child.type)
        child.each_descendant(*types, &block)
      end
    end
  end
end
end
