require 'bundler/setup'
require 'parser'
def debug *msg
  puts(*msg)if $debug
end

$debug = false

module Fast
  VERSION = "0.1.0"
  LITERAL = {
    '...' => -> (node) { !node.children.nil? },
    '_'   => -> (node) { debug "_? #{!node.nil?} : #{node}"; !node.nil? },
    'nil' => nil
  }

  class Find < Array
    def capturing?
      false
    end
  end
  class Capture < Array
    def capturing?
      true
    end
  end
  def self.expression(string)
    tokens = string.scan(/[A-z]+|\(|\)|\.{3}|_|\$/)

    stack = []
    context = []

    tokens.each do |token|
      if token == '('
        stack.push context
        context = []
      elsif token == ')'
        l = context
        context = stack.pop
        context << l
      else
        context << translate(token)
      end
    end
    tokens.include?("(") ? context.first : context
  end

  def self.parse(fast_tree)
    fast_tree.map do |token|
      translate(token) || token
    end
  end

  def self.translate(token)
    if token.is_a?(String)
      LITERAL.has_key?(token) ? LITERAL[token] : token.to_sym
    else
      token
    end
  end

  def self.capture(ast, fast, *levels)
    matcher = Matcher.new(ast, fast, capture_levels: levels)
    if matcher.match?
      matcher.captures
    else
      false
    end
  end
  def self.match?(ast, fast)
    Matcher.new(ast, fast).match?
  end

  class Matcher
    attr_reader :captures
    def initialize(ast, fast, capture_levels: [])
      @ast = ast
      @fast = fast
      @captures = []
      @capture_levels = capture_levels
    end

    def capturing?
      !@capture_levels.empty?
    end

    def match?(ast=@ast, fast=@fast, level: 0)
      fast = Fast.parse(fast)
      head = fast.shift
      return false unless match_node?(ast, head, level: level)
      if fast.empty?
        return true
      end

      results = fast.each_with_index.map do |token, i|
        child = ast.children[i]
        if token.is_a?(Enumerable)
          debug "calling recursive match?(#{child}, #{token})"
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
      results.uniq == [true]
    end

    def match_node? node, expression, level: 0
      debug "match_node?",node.inspect, "expression: '#{expression}'"
      matches =
        if expression.respond_to?(:call)
          expression.call(node)
        elsif expression.is_a?(Symbol)
          type = node.respond_to?(:type) ? node.type : node
          debug "#{type} == #{expression}"
          type == expression
        else
          debug "#{node.inspect} == #{expression.inspect}"
          node == expression
        end

      if matches && capturing?
        if @capture_levels.include?(level)
          capture = expression.is_a?(Symbol) ? node.type : node
          @captures << capture
        end
      end
      matches
    end
  end
end
