require 'bundler/setup'
require 'parser'
def debug *msg
  puts(*msg)if $debug
end


module Fast
  VERSION = "0.1.0"
  LITERAL = {
    '...' => -> (node) { !node.children.nil? },
    '_'   => -> (node) { debug "_? #{!node.nil?} : #{node}"; !node.nil? },
    'nil' => nil
  }

  def self.expression(string)
    tokens = string.scan(/[\+\-\/\*\dA-z]+[\!\?]?|\(|\)|\.{3}|_|\$/)
    stack = []
    context = []
    capturing = false

    tokens.each do |token|
      if token == '('
        stack.push context
        context = []
      elsif token == ')'
        l = context
        context = stack.pop
        context << l
        capturing = false
      elsif token == '$'
        capturing = true
      else
        expression = translate(token, capturing)
        context << expression
        capturing = false
      end
    end
    tokens.include?("(") ? context.first : context
  end

  def self.parse(fast_tree)
    fast_tree.map do |token|
      translate(token) || token
    end
  end

  class Find < Struct.new(:token)
    def capturing?
      false
    end

    def to_s
      token.inspect
    end

    def inspect
      "f(#{self})"
    end
  end

  class Capture <  Find
    def inspect
      "c(#{self})"
    end
    def capturing?
      true
    end
  end

  def self.translate(token, capturing=false)
    if token.is_a?(Find)
      token = Capture.new(token.token) if capturing
      return token
    end

    expression =
      if token.is_a?(String)
        LITERAL.has_key?(token) ? LITERAL[token] : token.to_sym
      else
        token
      end
    (capturing ? Capture : Find).new(expression)
  end

  def self.match?(ast, fast)
    Matcher.new(ast, fast).match?
  end

  class Matcher
    def initialize(ast, fast)
      @ast = ast
      @fast = fast
      @captures = []
    end

    def match?(ast=@ast, fast=@fast, level: 0)
      fast = Fast.expression(fast) if fast.is_a?(String)
      fast = Fast.parse(fast)
      head = fast.shift
      return false unless match_node?(ast, head, level: level)
      if fast.empty?
        return true if level > 0
        return @captures.empty? ? true : @captures
      end

      results = fast.each_with_index.map do |token, i|
        child = ast.children[i]
        if token.token.is_a?(Enumerable)
          debug "calling recursive match?(#{child.inspect}, #{token.class} #{token}, level: #{level + 1})"
          match?(child, token, level: level + 1)
        else
          matches = match_node?(child, token, level: level)
          if matches && token.respond_to?(:call)
            debug "token call returned true"
            next true
          end
          matches
        end
      end
      debug "results: #{ results.join(", ") }"
      if results.uniq == [true]
        @captures.empty? ? true : @captures
      else
        false
      end
    end

    def match_node? node, find, level: 0
      expression = find.token
      if $debug
        node_start_label = node.inspect.lines[0,3].join
        debug "#{find}.match_node?(#{node_start_label}...)"
      end

      matches =
        if expression.respond_to?(:call)
          debug "#proc call: #{expression}.call(#{node})"
          expression.call(node)
        elsif expression.is_a?(Symbol)
          type = node.respond_to?(:type) ? node.type : node
          debug "#type comparison: #{type} == #{expression}"
          type == expression
        elsif expression.is_a?(Enumerable)
          match?(node, expression, level: level + 1)
        else
          debug "#node comparison: #{node.inspect} == #{expression.inspect}"
          node == expression
        end

      if matches && find.capturing?
        @captures << node
      end

      matches
    end
  end
end
