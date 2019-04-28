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
    # @return [Astrolabe::Node] from the parsed content
    # @example
    #   Fast.ast("1") # => s(:int, 1)
    #   Fast.ast("a.b") # => s(:send, s(:send, nil, :a), :b)
    def ast(content, buffer_name: '(string)')
      buffer = Parser::Source::Buffer.new(buffer_name)
      buffer.source = content
      Parser::CurrentRuby.new(Astrolabe::Builder.new).parse(buffer)
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
    #   Fast.match?(Fast.ast("1"),"int") # => true
    def match?(ast, pattern, *args)
      Matcher.new(ast, pattern, *args).match?
    end

    # Replaces content based on a pattern.
    # @param [Astrolabe::Node] ast with the current AST to search.
    # @param [String] pattern with the expression to be targeting nodes.
    # @param [Proc] replacement gives the [Rewriter] context in the block.
    # @example
    #   Fast.replace?(Fast.ast("a = 1"),"lvasgn") do |node|
    #     replace(node.location.name, 'variable_renamed')
    #   end # => variable_renamed = 1
    # @return [String] with the new source code after apply the replacement
    # @see Fast::Rewriter
    def replace(ast, pattern, &replacement)
      buffer = Parser::Source::Buffer.new('replacement')
      buffer.source = ast.loc.expression.source
      to_replace = search(ast, pattern)
      types = to_replace.grep(Parser::AST::Node).map(&:type).uniq
      rewriter = Rewriter.new
      rewriter.buffer = buffer
      rewriter.search = pattern
      rewriter.replacement = replacement
      rewriter.replace_on(*types)
      rewriter.rewrite(buffer, ast)
    end

    # Replaces the source of an {Fast#ast_from_file} with
    # and the same source if the pattern does not match.
    def replace_file(file, pattern, &replacement)
      ast = ast_from_file(file)
      replace(ast, pattern, &replacement)
    end

    # Search with pattern directly on file
    # @return [Array<Astrolabe::Node>] that matches the pattern
    def search_file(pattern, file)
      node = ast_from_file(file)
      search node, pattern
    end

    # Capture elements from searches in files. Keep in mind you need to use `$`
    # in the pattern to make it work.
    # @return [Array<Object>] captured from the pattern matched in the file
    def capture_file(pattern, file)
      node = ast_from_file(file)
      capture node, pattern
    end

    # Search recursively into a node and its children.
    # If the node matches with the pattern it returns the node,
    # otherwise it recursively collect possible children nodes
    # @yield node and capture if block given
    def search(node, pattern)
      if (match = Fast.match?(node, pattern))
        yield node, match if block_given?
        match != true ? [node, match] : [node]
      else
        node.each_child_node
          .flat_map { |e| search(e, pattern) }
          .compact.flatten
      end
    end

    # Return only captures from a search
    # @return [Array<Object>] with all captured elements.
    # @return [Object] with single element when single capture.
    def capture(node, pattern)
      res =
        if (match = Fast.match?(node, pattern))
          match == true ? node : match
        else
          node.each_child_node
            .flat_map { |child| capture(child, pattern) }
            .compact.flatten
        end
      res&.size == 1 ? res[0] : res
    end

    def expression(string)
      ExpressionParser.new(string).parse
    end

    attr_accessor :debugging

    # Utility function to inspect search details using debug block.
    #
    # It prints output of all matching cases.
    #
    # @example
    #   Fast.debug do
    #      Fast.match?(s(:int, 1), [:int, 1])
    #   end
    #  int == (int 1) # => true
    #  1 == 1 # => true
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

    # @return [Array<String>] with all ruby files from arguments.
    # @param files can be file paths or directories.
    # When the argument is a folder, it recursively fetches all `.rb` files from it.
    def ruby_files_from(*files)
      directories = files.select(&File.method(:directory?))

      if directories.any?
        files -= directories
        files |= directories.flat_map { |dir| Dir["#{dir}/**/*.rb"] }
        files.uniq!
      end
      files
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
        children_expression = node.children.map(&Fast.method(:expression_from)).join(' ')
        "(#{node.type}#{' ' + children_expression if node.children.any?})"
      when nil, 'nil'
        'nil'
      when Symbol, String, Numeric
        '_'
      end
    end
  end

  # Rewriter encapsulates {Rewriter#match_index} to allow
  # {ExperimentFile.partial_replace} in a {Fast::ExperimentFile}.
  # @see https://www.rubydoc.info/github/whitequark/parser/Parser/TreeRewriter
  # @note the standalone class needs to combines {Rewriter#replace_on} to properly generate the `on_<node-type>` methods depending on the expression being used.
  # @example Simple Rewriter
  #    ast = Fast.ast("a = 1")
  #    buffer = Parser::Source::Buffer.new('replacement')
  #    buffer.source = ast.loc.expression.source
  #    rewriter = Rewriter.new
  #    rewriter.buffer = buffer
  #    rewriter.search ='(lvasgn _ ...)'
  #    rewriter.replacement =  -> (node) { replace(node.location.name, 'variable_renamed') }
  #    rewriter.replace_on(:lvasgn)
  #    rewriter.rewrite(buffer, ast) # => "variable_renamed = 1"
  class Rewriter < Parser::TreeRewriter
    # @return [Integer] with occurrence index
    attr_reader :match_index
    attr_accessor :buffer, :search, :replacement
    def initialize(*args)
      super
      @match_index = 0
    end

    def match?(node)
      Fast.match?(node, search)
    end

    # Generate methods for all affected types.
    # @see Fast.replace
    def replace_on(*types)
      types.map do |type|
        self.class.send :define_method, "on_#{type}" do |node|
          if captures = match?(node) # rubocop:disable Lint/AssignmentInCondition
            @match_index += 1
            execute_replacement(node, captures)
          end
          super(node)
        end
      end
    end

    # Execute {#replacement} block
    # @param [Astrolabe::Node] node that will be yield in the replacement block
    # @param [Array<Object>, nil] captures are yield if {#replacement} take second argument.
    def execute_replacement(node, captures)
      if replacement.parameters.length == 1
        instance_exec node, &replacement
      else
        instance_exec node, captures, &replacement
      end
    end
  end

  # ExpressionParser empowers the AST search in Ruby.
  # All classes inheriting Fast::Find have a grammar shortcut that is processed here.
  #
  # @example find a simple int node
  #   Fast.expression("int")
  #   # => #<Fast::Find:0x00007ffae39274e0 @token="int">
  # @example parens make the expression an array of Fast::Find and children classes
  #   Fast.expression("(int _)")
  #   # => [#<Fast::Find:0x00007ffae3a860e8 @token="int">, #<Fast::Find:0x00007ffae3a86098 @token="_">]
  # @example not int token
  #   Fast.expression("!int")
  #   # => #<Fast::Not:0x00007ffae43f35b8 @token=#<Fast::Find:0x00007ffae43f35e0 @token="int">>
  # @example int or float token
  #   Fast.expression("{int float}")
  #   # => #<Fast::Any:0x00007ffae43bbf00 @token=[
  #   #      #<Fast::Find:0x00007ffae43bbfa0 @token="int">,
  #   #      #<Fast::Find:0x00007ffae43bbf50 @token="float">
  #   #     #]>
  # @example capture something not nil
  #   Fast.expression("$_")
  #   # => #<Fast::Capture:0x00007ffae433a860 @captures=[], @token=#<Fast::Find:0x00007ffae433a888 @token="_">>
  # @example capture a hash with keys that all are not string and not symbols
  #   Fast.expression("(hash (pair ([!sym !str] _))")
  #   # => [#<Fast::Find:0x00007ffae3b45010 @token="hash">,
  #   #      [#<Fast::Find:0x00007ffae3b44f70 @token="pair">,
  #   #       [#<Fast::All:0x00007ffae3b44cf0 @token=[
  #   #         #<Fast::Not:0x00007ffae3b44e30 @token=#<Fast::Find:0x00007ffae3b44e80 @token="sym">>,
  #   #         #<Fast::Not:0x00007ffae3b44d40 @token=#<Fast::Find:0x00007ffae3b44d68 @token="str">>]>,
  #   #         #<Fast::Find:0x00007ffae3b44ca0 @token="_">]]]")")
  # @example of match using string expression
  #   Fast.match?(Fast.ast("{1 => 1}"),"(hash (pair ([!sym !str] _))") => true")")
  class ExpressionParser
    # @param expression [String]
    def initialize(expression)
      @tokens = expression.scan TOKENIZER
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

    private

    def next_token
      @tokens.shift
    end

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
      "f[#{[*token].map(&:to_s).join(', ')}]"
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
  # or sequential numbers considering the order of the captures.
  #
  # @example check comparision of integers that will always return true
  #   ast = Fast.ast("1 == 1") => s(:send, s(:int, 1), :==, s(:int, 1))
  #   Fast.match?(ast, "(send $(int _) == \1)") # => [s(:int, 1)]
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

  # Allow the user to interpolate expressions from external stuff.
  # Use `%1` in the expression and the Matcher#prepare_arguments will
  # interpolate the argument in the expression.
  # @example interpolate the node value 1
  #   Fast.match?(Fast.ast("1"), "(int %1)", 1) # => true
  #   Fast.match?(Fast.ast("1"), "(int %1)", 2) # => false
  # @example interpolate multiple arguments
  #   Fast.match?(Fast.ast("1"), "(%1 %2)", :int, 1) # => true
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

  # Capture some expression while searching for it.
  #
  # The captures behaves exactly like Fast::Find and the only difference is that
  # when it {#match?} stores #captures for future usage.
  #
  # @example capture int node
  #   capture = Fast::Capture.new("int") => #<Fast::Capture:0x00...e0 @captures=[], @token="int">
  #   capture.match?(Fast.ast("1")) # => [s(:int, 1)]
  #
  # @example binding directly in the Fast.expression
  #   Fast.match?(Fast.ast("1"), "(int $_)") # => [1]
  #
  # @example capture the value of a local variable assignment
  #   (${int float} _)
  # @example expression to capture only the node type
  #   (${int float} _)
  # @example expression to capture entire node
  #   $({int float} _)
  # @example expression to capture only the node value of int or float nodes
  #   ({int float} $_)
  # @example expression to capture both node type and value
  #   ($_ $_)
  #
  # You can capture stuff in multiple levels and
  # build expressions that  reference captures with Fast::FindWithCapture.
  class Capture < Find
    # Stores nodes that matches with the current expression.
    attr_reader :captures

    def initialize(token)
      super
      @captures = []
    end

    # Append the matching node to {#captures} if it matches
    def match?(node)
      @captures << node if super
    end

    def to_s
      "c[#{token}]"
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
  # @example Matchig int or float
  #   Fast.expression("{int float}")
  class Any < Find
    def match?(node)
      token.any? { |expression| Fast.match?(node, expression) }
    end

    def to_s
      "any[#{token.map(&:to_s).join(', ')}]"
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

  # Joins the AST and the search expression to create a complete matcher that
  # recusively check if the node pattern expression matches with the given AST.
  #
  ### Using captures
  #
  # One of the most important features of the matcher is find captures and also
  # bind them on demand in case the expression is using previous captures.
  #
  # @example simple match
  #   ast = Fast.ast("a = 1")
  #   expression = Fast.expression("(lvasgn _ (int _))")
  #   Matcher.new(ast,expression).match? # true
  #
  # @example simple capture
  #   ast = Fast.ast("a = 1")
  #   expression = Fast.expression("(lvasgn _ (int $_))")
  #   Matcher.new(ast,expression).match? # => [1]
  #
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

    # @return [true] if the @param ast recursively matches with expression.
    # @return #find_captures case matches
    def match?(ast = @ast, fast = @fast)
      head, *tail = fast
      return false unless head.match?(ast)
      return find_captures if tail.empty?

      match_tail?(ast.children, tail)
    end

    # @return [true] if all children matches with tail
    def match_tail?(child, tail)
      tail.each_with_index.all? do |token, i|
        prepare_token(token)
        token.is_a?(Array) ? match?(child[i], token) : token.match?(child[i])
      end && find_captures
    end

    # Look recursively into @param fast to check if the expression is have
    # captures.
    # @return [true] if any sub expression have captures.
    def captures?(fast = @fast)
      case fast
      when Capture then true
      when Array then fast.any?(&method(:captures?))
      when Find then captures?(fast.token)
      end
    end

    # Find search captures recursively.
    #
    # @return [Array<Object>] of captures from the expression
    # @return [true] in case of no captures in the expression
    # @see Fast::Capture
    # @see Fast::FindFromArgument
    def find_captures(fast = @fast)
      return true if fast == @fast && !captures?(fast)

      case fast
      when Capture then fast.captures
      when Array then fast.flat_map(&method(:find_captures)).compact
      when Find then find_captures(fast.token)
      end
    end

    private

    # Prepare arguments case the expression needs to bind extra arguments.
    # @return [void]
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

    # Prepare token  with previous captures
    # @param [FindWithCapture] token set the current captures
    # @return [void]
    # @see [FindWithCapture#previous_captures]
    def prepare_token(token)
      case token
      when Fast::FindWithCapture
        token.previous_captures = find_captures
      end
    end
  end
end
