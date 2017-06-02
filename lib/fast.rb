require 'bundler/setup'
require 'parser'

module Fast
  VERSION = "0.1.0"
  LITERAL = {
    '...' => -> (node) { node && !node.children.nil? },
    '_'   => -> (node) { !node.nil? },
    'nil' => nil
  }

  TOKENIZER = %r/
    [\+\-\/\*\\!]         # operators or negation
    |
    \d+\.\d*              # decimals and floats
    |
    _                     # something not nil: match
    |
    \.{3}                 # a node with children: ...
    |
    [\dA-z_]+[\\!\?]?     # method names or numbers
    |
    \(|\)                 # parens `(` and `)` for tuples
    |
    \{|\}                 # curly brackets `{` and `}` for any
    |
    \$                    # capture
  /x

  def self.match?(ast, fast)
    Matcher.new(ast, fast).match?
  end

  def self.expression(string)
    ExpressionParser.new(string).parse
  end

  def self.parse(fast_tree)
    fast_tree.map do |token|
      Find.new(token)
    end
  end

  class ExpressionParser
    def initialize(expression)
      @tokens = expression.scan TOKENIZER
    end

    def next_token
      @tokens.shift
    end

    def parse
      if (token = next_token) == '('
        parse_untill_peek(')')
      elsif token == '{'
        Any.new(parse_untill_peek('}'))
      elsif token == '$'
        Capture.new(parse)
      elsif token == '!'
        Not.new(parse)
      else
        Find.new(token)
      end
    end

    def parse_untill_peek(token)
      list = []
      list << parse until @tokens.first == token
      next_token
      list
    end
  end

  class Find < Struct.new(:token)
    def initialize(token)
      self.token = token
    end

    def match?(node)
      match_recursive(node, valuate(token))
    end

    def match_recursive(node, expression)
      if expression.respond_to?(:call)
        expression.call(node)
      elsif expression.is_a?(Find)
        expression.match?(node)
      elsif expression.is_a?(Symbol)
        type = node.respond_to?(:type) ? node.type : node
        type == expression
      elsif expression.respond_to?(:shift)
        match_recursive(node, expression.shift)
      else
        node == expression
      end
    end

    def to_s
      "f[#{token.map(&:to_s)}]"
    end

    private

    def valuate(token)
      if token.is_a?(String)
        if LITERAL.has_key?(token)
          LITERAL[token]
        elsif token =~ /\d+\.\d*/
          token.to_f
        elsif token =~ /\d+/
          token.to_i
        else
          token.to_sym
        end
      else
        token
      end
    end
  end

  class Capture <  Find
    attr_reader :captures
    def initialize(token)
      super
      @captures = []
    end

    def match? node
      if super
        @captures << node
      end
    end

    def to_s
      "c[#{token} $: #{@captures}]"
    end
  end

  class Any < Find
    def match?(node)
      token.any?{|expression| Fast.match?(node, expression) }
    end

    def to_s
      "any[#{token}]"
    end
  end

  class Not < Find
    def match?(node)
      !super
    end
  end

  class Matcher
    def initialize(ast, fast)
      @ast = ast
      if fast.is_a?(String)
        @fast = Fast.expression(fast)
      else
        @fast = Fast.parse(fast)
      end
      @captures = []
    end

    def match?(ast=@ast, fast=@fast)
      head,*tail = fast
      return false unless head.match?(ast)
      if tail.empty?
        return ast == @ast ? find_captures : true  # root node
      end
      child = ast.children
      return false if tail.size != child.size
      results = tail.each_with_index.map do |token, i|
        if token.is_a?(Array)
          match?(child[i], token)
        else
          token.match?(child[i])
        end
      end

      if results.any?{|e|e==false}
        return false
      else
        find_captures
      end
    end

    def find_captures(fast=@fast)
      [*fast].map do |f|
        case f
        when Capture
          f.captures
        when Array
          find_captures(f)
        end
      end.flatten.compact
    end
  end
end
