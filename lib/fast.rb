require 'bundler/setup'
require 'parser'

module Fast
  VERSION = "0.1.0"
  LITERAL = {
    '...' => -> (node) { !node.children.nil? },
    '_'   => -> (node) { !node.nil? },
  }

  def self.parse(fast_tree)
    fast_tree.map do |token|
      translate(token) || token
    end
  end

  def self.translate(token)
    LITERAL[token] || token
  end

  def self.match?(ast, fast_search)
    fast = parse(fast_search)
    #puts "Match>>>>>",ast, "Original: #{fast_search.inspect}, parsed: #{fast.inspect}"
    head = fast.shift
    return false unless match_node?(ast, head)
    # already validated on match_node?
    return true if head.respond_to?(:call) || ast.children.empty?
    ast.children.each_with_index.map do |child, i|
      if fast[i].is_a?(Enumerable)
        match?(child, fast[i])
      else
        matches = match_node?(child, fast[i])
        if matches && fast[i].respond_to?(:call)
          return true
        end
        matches
      end
    end.uniq == [true]
  end

  def self.match_node? node, expression
    #puts "match_node?",node.inspect, "expression: '#{expression}'"
    if expression.respond_to?(:call)
      expression.call(node)
    elsif expression.is_a?(Symbol)
      type = node.respond_to?(:type) ? node.type : node
      #puts "#{type} == #{expression}"
      type == expression
    else
      #puts "#{node.inspect} == #{expression.inspect}"
      node == expression
    end
  end
end
