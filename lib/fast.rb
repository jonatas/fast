# frozen_string_literal: true

require 'fileutils'
require 'astrolabe/builder'

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
  LITERAL = {
    '...' => ->(node) { node&.children&.any? },
    '_' => ->(node) { !node.nil? },
    'nil' => nil
  }.freeze

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
    [\d\w_]+[\\!\?]?      # method names or numbers
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

  class << self
    def match?(ast, search, *args)
      Matcher.new(ast, search, *args).match?
    end

    def replace(ast, search, replacement)
      buffer = Parser::Source::Buffer.new('replacement')
      buffer.source = ast.loc.expression.source
      to_replace = search(ast, search)
      types = to_replace.grep(Parser::AST::Node).map(&:type).uniq
      rewriter = Rewriter.new
      rewriter.buffer = buffer
      rewriter.search = search
      rewriter.replacement = replacement
      rewriter.affect_types(*types)
      rewriter.rewrite(buffer, ast)
    end

    def replace_file(file, search, replacement)
      ast = ast_from_file(file)
      replace(ast, search, replacement)
    end

    def search_file(pattern, file)
      node = ast_from_file(file)
      search node, pattern
    end

    def capture_file(pattern, file)
      node = ast_from_file(file)
      capture node, pattern
    end

    def search(node, pattern)
      if (match = Fast.match?(node, pattern))
        yield node, match if block_given?
        match != true ? [node, match] : [node]
      elsif Fast.match?(node, '...')
        node.each_child_node
          .flat_map { |e| search(e, pattern) }
          .compact.flatten
      end
    end

    def capture(node, pattern)
      res =
        if (match = Fast.match?(node, pattern))
          match == true ? node : match
        elsif node.child_nodes.any?
          node.each_child_node
            .flat_map { |child| capture(child, pattern) }
            .compact.flatten
        end
      res&.size == 1 ? res[0] : res
    end

    def ast(content, buffer_name: '(string)')
      buffer = Parser::Source::Buffer.new(buffer_name)
      buffer.source = content
      Parser::CurrentRuby.new(Astrolabe::Builder.new).parse(buffer)
    end

    def ast_from_file(file)
      @cache ||= {}
      @cache[file] ||= ast(IO.read(file), buffer_name: file)
    end

    def highlight(node, show_sexp: false)
      output =
        if node.respond_to?(:loc) && !show_sexp
          node.loc.expression.source
        else
          node
        end
      CodeRay.scan(output, :ruby).term
    end

    def report(result, show_sexp: nil, file: nil)
      if file
        line = result.loc.expression.line if result.is_a?(Parser::AST::Node)
        puts Fast.highlight("# #{file}:#{line}")
      end
      puts Fast.highlight(result, show_sexp: show_sexp)
    end

    def expression(string)
      ExpressionParser.new(string).parse
    end
    attr_accessor :debugging

    def debug
      return yield if debugging

      self.debugging = true
      result = nil
      Find.class_eval do
        alias_method :original_match_recursive, :match_recursive
        alias_method :match_recursive, :debug_match_recursive
        result = yield
        alias_method :match_recursive, :original_match_recursive # rubocop:disable Lint/DuplicateMethods
      end
      self.debugging = false
      result
    end

    def ruby_files_from(*files)
      directories = files.select(&File.method(:directory?))

      if directories.any?
        files -= directories
        files |= directories.flat_map { |dir| Dir["#{dir}/**/*.rb"] }
        files.uniq!
      end
      files
    end

    def expression_from(node)
      case node
      when Parser::AST::Node
        children_expression = node.children.map(&Fast.method(:expression_from)).join(' ')
        "(#{node.type}#{' ' + children_expression if node.children.any?})"
      when nil, 'nil'
        'nil'
      when Symbol, String, Numeric
        '_'
      when Array, Hash
        '...'
      end
    end
  end

  # Rewriter encapsulates `#match_index` allowing to rewrite only specific matching occurrences
  # into the file. It empowers the `Fast.experiment`  and offers some useful insights for running experiments.
  class Rewriter < Parser::TreeRewriter
    attr_reader :match_index
    attr_accessor :buffer, :search, :replacement
    def initialize(*args)
      super
      @match_index = 0
    end

    def match?(node)
      Fast.match?(node, search)
    end

    def affect_types(*types) # rubocop:disable Metrics/MethodLength
      types.map do |type|
        self.class.send :define_method, "on_#{type}" do |node|
          if captures = match?(node) # rubocop:disable Lint/AssignmentInCondition
            @match_index += 1
            if replacement.parameters.length == 1
              instance_exec node, &replacement
            else
              instance_exec node, captures, &replacement
            end
          end
          super(node)
        end
      end
    end
  end

  # ExpressionParser empowers the AST search in Ruby.
  # You can check a few classes inheriting `Fast::Find` and adding extra behavior.
  # Parens encapsulates node search: `(node_type children...)` .
  # Exclamation Mark to negate: `!(int _)` is equivalent to a `not integer` node.
  # Curly Braces allows [Any]: `({int float} _)`  or `{(int _) (float _)}`.
  # Square Braquets allows [All]: [(int _) !(int 0)] # all integer less zero.
  # Dollar sign can be used to capture values: `(${int float} _)` will capture the node type.
  class ExpressionParser
    def initialize(expression)
      @tokens = expression.scan TOKENIZER
    end

    def next_token
      @tokens.shift
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    def parse
      case (token = next_token)
      when '(' then parse_until_peek(')')
      when '{' then Any.new(parse_until_peek('}'))
      when '[' then All.new(parse_until_peek(']'))
      when /^"/ then FindString.new(token[1..-2])
      when /^#\w/ then MethodCall.new(token[1..-1])
      when /^\.\w[\w\d_]+\?/ then InstanceMethodCall.new(token[1..-1])
      when '$' then Capture.new(parse)
      when '!' then (@tokens.any? ? Not.new(parse) : Find.new(token))
      when '?' then Maybe.new(parse)
      when '^' then Parent.new(parse)
      when '\\' then FindWithCapture.new(parse)
      when /^%\d/ then FindFromArgument.new(token[1..-1])
      else Find.new(token)
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength

    def parse_until_peek(token)
      list = []
      list << parse until @tokens.empty? || @tokens.first == token
      next_token
      list
    end
  end

  # Find is the top level class that respond to #match?(node) interface.
  # It matches recurively and check deeply depends of the token type.
  class Find
    attr_accessor :token
    def initialize(token)
      self.token = token
    end

    def match?(node)
      match_recursive(node, valuate(token))
    end

    def match_recursive(node, expression)
      case expression
      when Proc then expression.call(node)
      when Find then expression.match?(node)
      when Symbol then compare_symbol_or_head(node, expression)
      when Enumerable
        expression.each_with_index.all? do |exp, i|
          match_recursive(i.zero? ? node : node.children[i - 1], exp)
        end
      else
        node == expression
      end
    end

    def compare_symbol_or_head(node, expression)
      case node
      when Parser::AST::Node
        node.type == expression.to_sym
      when String
        node == expression.to_s
      else
        node == expression
      end
    end

    def debug_match_recursive(node, expression)
      match = original_match_recursive(node, expression)
      debug(node, expression, match)
      match
    end

    def debug(node, expression, match)
      puts "#{expression} == #{node} # => #{match}"
    end

    def to_s
      "f[#{[*token].join(', ')}]"
    end

    def ==(other)
      return false if other.nil? || !other.respond_to?(:token)

      token == other.token
    end

    private

    def valuate(token)
      if token.is_a?(String)
        return valuate(LITERAL[token]) if LITERAL.key?(token)

        typecast_value(token)
      else
        token
      end
    end

    def typecast_value(token)
      case token
      when /\d+\.\d*/ then token.to_f
      when /\d+/ then token.to_i
      else token.to_sym
      end
    end
  end

  # Find literal strings using double quotes
  class FindString < Find
    def initialize(token)
      @token = token
    end

    def match?(node)
      node == token
    end
  end

  # Find using custom methods
  class MethodCall < Find
    def initialize(method_name)
      @method_name = method_name
    end

    def match?(node)
      Kernel.send(@method_name, node)
    end
  end

  # Search using custom instance methods
  class InstanceMethodCall < Find
    def initialize(method_name)
      @method_name = method_name
    end

    def match?(node)
      node.send(@method_name)
    end
  end

  # Allow use previous captures while searching in the AST.
  # Use `\\1` to point the match to the first captured element
  class FindWithCapture < Find
    attr_writer :previous_captures

    def initialize(token)
      token = token.token if token.respond_to?(:token)
      raise 'You must use captures!' unless token

      @capture_index = token.to_i
    end

    def match?(node)
      node == @previous_captures[@capture_index - 1]
    end

    def to_s
      "fc[\\#{@capture_index}]"
    end
  end

  # Use `%1` in the expression and the Matcher#prepare_arguments will
  # interpolate the argument in the expression.
  class FindFromArgument < Find
    attr_writer :arguments

    def initialize(token)
      token = token.token if token.respond_to?(:token)
      raise 'You must define index' unless token

      @capture_argument = token.to_i - 1
      raise 'Arguments start in one' if @capture_argument.negative?
    end

    def match?(node)
      raise 'You must define arguments to match' unless @arguments

      compare_symbol_or_head node, @arguments[@capture_argument]
    end

    def to_s
      "find_with_arg[\\#{@capture_argument}]"
    end
  end

  # Capture some expression while searching for it:
  # Example: `(${int float} _)` will capture the node type
  # Example: `$({int float} _)` will capture the node
  # Example: `({int float} $_)` will capture the value
  # Example: `(${int float} $_)` will capture both node type and value
  # You can capture multiple levels
  class Capture < Find
    attr_reader :captures
    def initialize(token)
      super
      @captures = []
    end

    def match?(node)
      @captures << node if super
    end

    def to_s
      "c[#{token} $: #{@captures}]"
    end
  end

  # Sometimes you want to check some children but get the parent element,
  # for such cases,  parent can be useful.
  # Example: You're searching for `int` usages in your code.
  # But you don't want to check the integer itself, but who is using it:
  # `^^(int _)` will give you the variable being assigned or the expression being used.
  class Parent < Find
    alias match_node match?
    def match?(node)
      node.each_child_node.any?(&method(:match_node))
    end

    def to_s
      "^#{token}"
    end
  end

  # Matches any of the internal expressions. Works like a **OR** condition.
  # `{int float}` means int or float.
  class Any < Find
    def match?(node)
      token.any? { |expression| Fast.match?(node, expression) }
    end

    def to_s
      "any[#{token}]"
    end
  end

  # Intersect expressions. Works like a **AND** operator.
  class All < Find
    def match?(node)
      token.all? { |expression| expression.match?(node) }
    end

    def to_s
      "all[#{token}]"
    end
  end

  # Negates the current expression
  # `!int` is equilvalent to "not int"
  class Not < Find
    def match?(node)
      !super
    end
  end

  # True if the node does not exist
  # When exists, it should match.
  class Maybe < Find
    def match?(node)
      node.nil? || super
    end
  end

  # Joins the AST and the search expression to create a complete match
  class Matcher
    def initialize(ast, fast, *args)
      @ast = ast
      @fast = if fast.is_a?(String)
                Fast.expression(fast)
              else
                [*fast].map(&Find.method(:new))
              end
      @captures = []
      prepare_arguments(@fast, args) if args.any?
    end

    def prepare_arguments(expression, arguments)
      case expression
      when Array
        expression.each do |item|
          prepare_arguments(item, arguments)
        end
      when Fast::FindFromArgument
        expression.arguments = arguments
      when Fast::Find
        prepare_arguments expression.token, arguments
      end
    end
    def match?(ast = @ast, fast = @fast)
      head, *tail = fast
      return false unless head.match?(ast)
      if tail.empty?
        return ast == @ast ? find_captures : true # root node
      end

      child = ast.children
      tail.each_with_index.all? do |token, i|
        prepare_token(token)
        token.is_a?(Array) ? match?(child[i], token) : token.match?(child[i])
      end && find_captures
    end

    # rubocop:enable Metrics/AbcSize

    def prepare_token(token)
      case token
      when Fast::FindWithCapture
        token.previous_captures = find_captures
      end
    end

    def captures?(fast = @fast)
      case fast
      when Capture then true
      when Array then fast.any?(&method(:captures?))
      when Find then captures?(fast.token)
      end
    end

    def find_captures(fast = @fast)
      return true if fast == @fast && !captures?(fast)

      case fast
      when Capture then fast.captures
      when Array then fast.flat_map(&method(:find_captures)).compact
      when Find then find_captures(fast.token)
      end
    end
  end
end
