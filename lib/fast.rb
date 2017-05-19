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
    debug "Match>>>>>",ast, "Original: #{fast_search.inspect}, parsed: #{fast.inspect}"
    head = fast.shift
    return false unless match_node?(ast, head)
    # already validated on match_node?
    if fast.empty?
      return true
    end

    results = fast.each_with_index.map do |token, i|
      child = ast.children[i]
      if token.is_a?(Enumerable)
        debug "calling recursive match?(#{child}, #{token})"
        match?(child, token)
      else
        matches = match_node?(child, token)
        if matches && token.respond_to?(:call)
          debug "fast i is a call return true"
          next true
        end
        matches
      end
    end
    debug "results: #{ results.join(", ") }"
    results.uniq == [true]
  end

  def self.match_node? node, expression
    debug "match_node?",node.inspect, "expression: '#{expression}'"
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
  end
end
