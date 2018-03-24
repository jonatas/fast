# frozen_string_literal: true

$LOAD_PATH << File.expand_path('../lib', __dir__)
require 'fast'

def node_size(node)
  return 1 unless node.respond_to?(:children)
  children = node.children
  return 1 if children.empty? || children.length == 1
  nodes, syms = children.partition { |e| e.respond_to?(:children) }
  1 + syms.length + (nodes.map(&method(:node_size)).inject(:+) || 0)
end

def method_complexity(file)
  ast = Fast.ast_from_file(file)
  Fast.search(ast, '(class ...)').map do |node_class|
    manager_name = node_class.children.first.children.last

    defs = Fast.search(node_class, '(def !{initialize} ... ... )')

    defs.map do |node|
      complexity = node_size(node)
      method_name = node.children.first
      { "#{manager_name}##{method_name}" => complexity }
    end.inject(:merge) || {}
  end
end

files = ARGV || Dir['**/*.rb']

complexities = files.map(&method(:method_complexity)).flatten.inject(:merge!)

puts '| Method | Complexity |'
puts '| ------ | ---------- |'
complexities.sort_by { |_, v| -v }.map do |method, complexity|
  puts "| #{method} | #{complexity} |"
end
