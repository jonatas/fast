require 'bundler/setup'
require 'parser'
def debug *msg
  puts(*msg)if $debug
end

module Fast
  VERSION = "0.1.0"
  LITERAL = {
    '...' => -> (node) { !node.children.nil? },
    '_'   => -> (node) { !node.nil? },
    'nil' => nil
  }


  TOKENIZER = /[\+\-\/\*\dA-z]+[\!\?]?|\(|\)|\{|\}|\.{3}|_|\$/

  def self.expression(string)
    tokens = string.scan(TOKENIZER)
    stack = []
    context = []
    capturing = false
    capturing_exp = nil
    tokens.each do |token|
      if token == '(' || token == '{'
        if capturing
          capturing_exp = token
          capturing = false
        end
        stack.push context
        context = []
      elsif token == ')'
        expression = context
        if capturing_exp == "("
          expression = Capture.new(expression)
          capturing_exp = nil
          capturing = false
        end
        context = stack.pop || stack.push([]).pop
        context << expression
      elsif token == '$'
        capturing = true
      elsif token == '}'
        expression = Union.new(context)
        if capturing_exp == "{"
          expression = Capture.new(expression)
          capturing_exp = nil
          capturing = false
        end
        context = stack.pop
        context << expression
      else
        expression = translate(token)
        if capturing
          expression = if expression.is_a?(Find) 
                         Capture.new(expression.token)
                       else
                         Capture.new(expression)
                       end
          capturing = false
        end
        context << expression
      end
    end
    context.size == 1 ? context.first : context
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
        type == expression
      elsif expression.respond_to?(:shift)
        match_recursive(node, expression.shift)
      else
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
      debug "and parsed #{@fast} becomes #{fast}"

      head,*tail = fast
      return false unless head.match?(ast)
      if tail.empty?
        return ast == @ast ? find_captures : true  # root node
      end
      child = ast.children
      results = tail.each_with_index.map do |token, i|
        if token.is_a?(Array)
          result = match?(child[i], token)
          debug "calling recursive match?(#{child[i].inspect}, #{token.class} #{token}) =>>>>>>>>#{ result } "
          result
        else
          matches = token.match?(child[i])
          if matches && token.respond_to?(:call)
            debug "token call =>>>>>> true"
            next true
          end 
          debug "token is a proc and returned =>>>>>> #{matches}"
          matches
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
