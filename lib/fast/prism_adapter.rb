# frozen_string_literal: true

require 'parser'
require 'prism'

module Fast
  module PrismAdapter
    module_function

    class Location
      attr_reader :expression

      def initialize(buffer_name, source, start_offset, end_offset)
        buffer = Parser::Source::Buffer.new(buffer_name)
        buffer.source = source
        @expression = Parser::Source::Range.new(buffer, start_offset, end_offset)
      end
    end

    class Node
      attr_reader :type, :children, :loc
      attr_accessor :parent

      def initialize(type, children:, loc:)
        @type = type
        @children = Array(children)
        @loc = loc
        assign_parents!
      end

      def expression
        loc.expression
      end

      def source
        expression.source
      end

      def each_child_node
        return enum_for(:each_child_node) unless block_given?

        children.select { |child| child.respond_to?(:type) && child.respond_to?(:children) }.each { |child| yield child }
      end

      def each_descendant(*types, &block)
        return enum_for(:each_descendant, *types) unless block_given?

        each_child_node do |child|
          yield child if types.empty? || types.include?(child.type)
          child.each_descendant(*types, &block)
        end
      end

      def search(pattern, *args)
        Fast.search(pattern, self, *args)
      end

      def capture(pattern, *args)
        Fast.capture(pattern, self, *args)
      end

      def root?
        parent.nil?
      end

      def respond_to_missing?(method_name, include_private = false)
        method_name.to_s.end_with?('_type?') || super
      end

      def method_missing(method_name, *args, &block)
        if method_name.to_s.end_with?('_type?') && args.empty? && !block
          return type == method_name.to_s.delete_suffix('_type?').to_sym
        end

        super
      end

      private

      def assign_parents!
        each_child_node do |child|
          child.parent = self
        end
      end
    end

    def parse(source, buffer_name: '(string)')
      result = Prism.parse(source)
      return unless result.success?

      adapt(result.value, source, buffer_name)
    end

    def adapt(node, source, buffer_name)
      return if node.nil?

      case node
      when Prism::ProgramNode
        statements = adapt_statements(node.statements, source, buffer_name)
        statements.is_a?(Node) ? statements : build_node(:begin, statements, node, source, buffer_name)
      when Prism::StatementsNode
        adapt_statements(node, source, buffer_name)
      when Prism::ModuleNode
        build_node(:module, [adapt(node.constant_path, source, buffer_name), adapt(node.body, source, buffer_name)], node, source, buffer_name)
      when Prism::ClassNode
        build_node(:class, [adapt(node.constant_path, source, buffer_name), adapt(node.superclass, source, buffer_name), adapt(node.body, source, buffer_name)], node, source, buffer_name)
      when Prism::SingletonClassNode
        build_node(:sclass, [adapt(node.expression, source, buffer_name), adapt(node.body, source, buffer_name)], node, source, buffer_name)
      when Prism::DefNode
        if node.receiver
          build_node(:defs, [adapt(node.receiver, source, buffer_name), node.name, adapt_parameters(node.parameters, source, buffer_name), adapt(node.body, source, buffer_name)], node, source, buffer_name)
        else
          build_node(:def, [node.name, adapt_parameters(node.parameters, source, buffer_name), adapt(node.body, source, buffer_name)], node, source, buffer_name)
        end
      when Prism::BlockNode
        build_node(:block, [adapt(node.call, source, buffer_name), adapt_block_parameters(node.parameters, source, buffer_name), adapt(node.body, source, buffer_name)], node, source, buffer_name)
      when Prism::CallNode
        children = [adapt(node.receiver, source, buffer_name), node.name]
        children.concat(node.arguments&.arguments.to_a.map { |arg| adapt(arg, source, buffer_name) } || [])
        build_node(:send, children, node, source, buffer_name)
      when Prism::ConstantPathNode
        build_const_path(node, source, buffer_name)
      when Prism::ConstantReadNode
        build_node(:const, [nil, node.name], node, source, buffer_name)
      when Prism::ConstantWriteNode
        build_node(:casgn, [nil, node.name, adapt(node.value, source, buffer_name)], node, source, buffer_name)
      when Prism::SymbolNode
        build_node(:sym, [node.unescaped], node, source, buffer_name)
      when Prism::StringNode
        build_node(:str, [node.unescaped], node, source, buffer_name)
      when Prism::ArrayNode
        build_node(:array, node.elements.map { |child| adapt(child, source, buffer_name) }, node, source, buffer_name)
      when Prism::HashNode
        build_node(:hash, node.elements.map { |child| adapt(child, source, buffer_name) }, node, source, buffer_name)
      when Prism::AssocNode
        build_node(:pair, [adapt(node.key, source, buffer_name), adapt(node.value, source, buffer_name)], node, source, buffer_name)
      when Prism::SelfNode
        build_node(:self, [], node, source, buffer_name)
      when Prism::LocalVariableReadNode
        build_node(:lvar, [node.name], node, source, buffer_name)
      when Prism::InstanceVariableReadNode
        build_node(:ivar, [node.name], node, source, buffer_name)
      when Prism::InstanceVariableWriteNode, Prism::InstanceVariableOrWriteNode
        build_node(:ivasgn, [node.name, adapt(node.value, source, buffer_name)], node, source, buffer_name)
      when Prism::LocalVariableWriteNode, Prism::LocalVariableOrWriteNode
        build_node(:lvasgn, [node.name, adapt(node.value, source, buffer_name)], node, source, buffer_name)
      when Prism::IntegerNode
        build_node(:int, [node.value], node, source, buffer_name)
      when Prism::FloatNode
        build_node(:float, [node.value], node, source, buffer_name)
      when Prism::TrueNode
        build_node(:true, [], node, source, buffer_name)
      when Prism::FalseNode
        build_node(:false, [], node, source, buffer_name)
      when Prism::NilNode
        build_node(:nil, [], node, source, buffer_name)
      when Prism::IfNode
        build_node(:if, [adapt(node.predicate, source, buffer_name), adapt(node.statements, source, buffer_name), adapt(node.consequent, source, buffer_name)], node, source, buffer_name)
      when Prism::UnlessNode
        build_node(:if, [adapt(node.predicate, source, buffer_name), adapt(node.consequent, source, buffer_name), adapt(node.statements, source, buffer_name)], node, source, buffer_name)
      when Prism::BeginNode, Prism::EmbeddedStatementsNode
        statements = adapt_statements(node.statements, source, buffer_name)
        statements.is_a?(Node) ? statements : build_node(:begin, statements, node, source, buffer_name)
      when Prism::LambdaNode
        build_node(:lambda, [adapt_block_parameters(node.parameters, source, buffer_name), adapt(node.body, source, buffer_name)], node, source, buffer_name)
      else
        nil
      end
    end

    def adapt_statements(node, source, buffer_name)
      return nil unless node

      children = node.body.filter_map { |child| adapt(child, source, buffer_name) }
      return nil if children.empty?
      return children.first if children.one?

      build_node(:begin, children, node, source, buffer_name)
    end

    def adapt_parameters(node, source, buffer_name)
      return build_node(:args, [], nil, source, buffer_name) unless node

      children = []
      children.concat(node.requireds.map { |child| build_node(:arg, [child.name], child, source, buffer_name) }) if node.respond_to?(:requireds)
      children.concat(node.optionals.map { |child| build_node(:optarg, [child.name, adapt(child.value, source, buffer_name)], child, source, buffer_name) }) if node.respond_to?(:optionals)
      children << build_node(:restarg, [parameter_name(node.rest)], node.rest, source, buffer_name) if node.respond_to?(:rest) && node.rest
      children.concat(node.posts.map { |child| build_node(:arg, [child.name], child, source, buffer_name) }) if node.respond_to?(:posts)
      children.concat(node.keywords.map { |child| adapt_keyword_parameter(child, source, buffer_name) }) if node.respond_to?(:keywords)
      children << build_node(:kwrestarg, [parameter_name(node.keyword_rest)], node.keyword_rest, source, buffer_name) if node.respond_to?(:keyword_rest) && node.keyword_rest
      children << build_node(:blockarg, [parameter_name(node.block)], node.block, source, buffer_name) if node.respond_to?(:block) && node.block
      build_node(:args, children, node, source, buffer_name)
    end

    def adapt_block_parameters(node, source, buffer_name)
      return build_node(:args, [], nil, source, buffer_name) unless node

      params = node.respond_to?(:parameters) ? node.parameters : node
      adapt_parameters(params, source, buffer_name)
    end

    def adapt_keyword_parameter(node, source, buffer_name)
      case node
      when Prism::RequiredKeywordParameterNode
        build_node(:kwarg, [node.name], node, source, buffer_name)
      when Prism::OptionalKeywordParameterNode
        build_node(:kwoptarg, [node.name, adapt(node.value, source, buffer_name)], node, source, buffer_name)
      else
        build_node(:arg, [node.name], node, source, buffer_name)
      end
    end

    def parameter_name(node)
      node.respond_to?(:name) ? node.name : nil
    end

    def build_const_path(node, source, buffer_name)
      parent = node.parent ? adapt(node.parent, source, buffer_name) : nil
      build_node(:const, [parent, node.child.name], node, source, buffer_name)
    end

    def build_node(type, children, prism_node, source, buffer_name)
      loc =
        if prism_node
          Location.new(buffer_name, source, prism_node.location.start_offset, prism_node.location.end_offset)
        else
          Location.new(buffer_name, source, 0, 0)
        end
      Node.new(type, children: children, loc: loc)
    end
  end
end
