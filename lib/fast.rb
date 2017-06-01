require 'bundler/setup'
require 'parser'

def debug *msg
  puts(*msg)if $debug
end

module Fast
  VERSION = "0.1.0"
  LITERAL = {
    '...' => -> (node) { node && !node.children.nil? },
    '_'   => -> (node) { !node.nil? },
    'nil' => nil
  }

  TOKENIZER = /[\+\-\/\*]|[\dA-z]+[\!\?]?|\(|\)|\{|\}|\.{3}|_|\$/

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
        Union.new(parse_untill_peek('}'))
      elsif token == '$'
        Capture.new(parse)
      else
        Fast.translate(token)
      end
    end

    def parse_untill_peek(token)
      list = []
      list << parse until @tokens.first == token
      next_token
      list
    end
  end

  def self.expression(string)
    ExpressionParser.new(string).parse
  end

  def self.parse(fast_tree)
    fast_tree.map do |token|
      translate(token) || token
    end
  end

  class Find < Struct.new(:token)

    def match?(node)
      match_recursive(node, token)
    end

    def match_recursive(node, expression)
      if expression.respond_to?(:call)
        expression.call(node)
      elsif expression.is_a?(Find)
        expression.match?(node)
      elsif expression.is_a?(Symbol)
        type = node.respond_to?(:type) ? node.type : node
        debug "comparing type #{type} == #{expression} => #{type == expression}"
        type == expression
      elsif expression.respond_to?(:shift)
        match_recursive(node, expression.shift)
      else
        debug "comparing #{node} == #{expression} => #{node == expression}"
        node == expression
      end
    end

    def to_s
      token.inspect
    end

    def inspect
      "f(#{self})"
    end
  end

  class Capture <  Find
    attr_reader :captures
    def initialize(token)
      self.token = token
      @captures = []
    end

    def match? node
      if super
        @captures << node
      end
    end

    def inspect
      "c(#{self})"
    end
  end

  class Union < Find
    def match?(node)
      token.any?{|expression| Fast.match?(node, expression) }
    end

    def inspect
      "union(#{token})"
    end
  end

  def self.translate(token)
    if token.is_a?(Find)
      return token
    end

    expression =
      if token.is_a?(String)
        if LITERAL.has_key?(token)
          LITERAL[token]
        else
          token.to_sym
        end
      else
        token
      end
    Find.new(expression)
  end

  def self.match?(ast, fast)
    Matcher.new(ast, fast).match?
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
