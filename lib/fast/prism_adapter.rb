# frozen_string_literal: true

require 'prism'

module Fast
  # Adapts Prism AST to Fast AST
  module PrismAdapter
    # Location allows to track the source code range from the Prism location
    class Location < Fast::Source::Range
      attr_accessor :node

      def initialize(buffer_name, source, start_offset, end_offset, prism_node: nil)
        @prism_node = prism_node
        @buffer_name = buffer_name
        @source = source
        source_buffer = Fast::Source::Buffer.new(buffer_name, source: source)
        super(source_buffer, start_offset, end_offset)
      end

      def name
        return unless @prism_node&.respond_to?(:name_loc) && @prism_node.name_loc

        range_for(@prism_node.name_loc)
      end

      def selector
        return unless @prism_node&.respond_to?(:message_loc) && @prism_node.message_loc

        range_for(@prism_node.message_loc)
      end

      def operator
        return unless @prism_node&.respond_to?(:operator_loc) && @prism_node.operator_loc

        range_for(@prism_node.operator_loc)
      end

      def expression
        self
      end

      private

      def range_for(prism_location)
        Fast::Source::Range.new(
          source_buffer,
          character_offset(@source, prism_location.start_offset),
          character_offset(@source, prism_location.end_offset)
        )
      end

      def character_offset(source, byte_offset)
        source.byteslice(0, byte_offset).length
      end
    end

    class << self
      def parse(source, buffer_name: '(string)')
        result = Prism.parse(source)
        return unless result.success?

        adapt(result.value, source, buffer_name)
      end

      def adapt(node, source, buffer_name)
        return if node.nil?

        case node
        when Symbol
          build_node(:sym, [node.to_s], nil, source, buffer_name)
        when String
          build_node(:str, [node], nil, source, buffer_name)
        when Prism::ProgramNode
          statements = adapt_statements(node.statements, source, buffer_name)
          statements.is_a?(Node) ? statements : build_node(:begin, statements, node, source, buffer_name)
        when Prism::StatementsNode
          adapt_statements(node, source, buffer_name)
        when Prism::AliasMethodNode, Prism::AliasGlobalVariableNode
          build_node(:alias, [adapt(node.new_name, source, buffer_name), adapt(node.old_name, source, buffer_name)], node, source, buffer_name)
        when Prism::DefinedNode
          build_node(:defined?, [adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::UndefNode
          build_node(:undef, node.names.map { |name| adapt(name, source, buffer_name) }, node, source, buffer_name)
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
          return nil unless node.respond_to?(:call)

          build_node(:block, [adapt_call_node(node.call, source, buffer_name), adapt_block_parameters(node.parameters, source, buffer_name), adapt(node.body, source, buffer_name)], node, source, buffer_name)
        when Prism::CallNode
          if node.respond_to?(:block) && node.block.is_a?(Prism::BlockNode)
            return build_node(
              :block,
              [
                adapt_call_node(node, source, buffer_name),
                adapt_block_parameters(node.block.parameters, source, buffer_name),
                adapt(node.block.body, source, buffer_name)
              ],
              node,
              source,
              buffer_name
            )
          end

          adapt_call_node(node, source, buffer_name)
        when Prism::ParenthesesNode
          adapt(node.body, source, buffer_name)
        when Prism::RangeNode
          build_node(node.exclude_end? ? :erange : :irange, [adapt(node.left, source, buffer_name), adapt(node.right, source, buffer_name)], node, source, buffer_name)
        when Prism::BlockArgumentNode
          build_node(:block_pass, [adapt(node.expression, source, buffer_name)], node, source, buffer_name)
        when Prism::ReturnNode
          build_node(:return, node.arguments&.arguments.to_a.map { |arg| adapt(arg, source, buffer_name) }, node, source, buffer_name)
        when Prism::NextNode
          build_node(:next, node.arguments&.arguments.to_a.map { |arg| adapt(arg, source, buffer_name) }, node, source, buffer_name)
        when Prism::BreakNode
          build_node(:break, node.arguments&.arguments.to_a.map { |arg| adapt(arg, source, buffer_name) }, node, source, buffer_name)
        when Prism::YieldNode
          build_node(:yield, node.arguments&.arguments.to_a.map { |arg| adapt(arg, source, buffer_name) }, node, source, buffer_name)
        when Prism::SuperNode
          build_node(:super, node.arguments&.arguments.to_a.map { |arg| adapt(arg, source, buffer_name) }, node, source, buffer_name)
        when Prism::ForwardingSuperNode
          build_node(:zsuper, [], node, source, buffer_name)
        when Prism::SplatNode
          build_node(:splat, [adapt(node.expression, source, buffer_name)], node, source, buffer_name)
        when Prism::AssocSplatNode
          build_node(:kwsplat, [adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::ConstantPathNode
          build_const_path(node, source, buffer_name)

        when Prism::ConstantReadNode
          build_node(:const, [nil, node.name], node, source, buffer_name)
        when Prism::ConstantWriteNode
          build_node(:casgn, [nil, node.name, adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::ConstantPathWriteNode
          build_node(:casgn, [adapt(node.target, source, buffer_name), nil, adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::SymbolNode
          build_node(:sym, [node.unescaped], node, source, buffer_name)
        when Prism::StringNode
          build_node(:str, [node.unescaped], node, source, buffer_name)
        when Prism::XStringNode
          build_node(:xstr, [node.unescaped], node, source, buffer_name)
        when Prism::InterpolatedStringNode
          build_node(:dstr, node.parts.filter_map { |part| adapt(part, source, buffer_name) }, node, source, buffer_name)
        when Prism::InterpolatedXStringNode
          build_node(:dxstr, node.parts.filter_map { |part| adapt(part, source, buffer_name) }, node, source, buffer_name)
        when Prism::EmbeddedStatementsNode
          build_node(:begin, [adapt(node.statements, source, buffer_name)], node, source, buffer_name)
        when Prism::InterpolatedSymbolNode
          build_node(:dsym, node.parts.filter_map { |part| adapt(part, source, buffer_name) }, node, source, buffer_name)
        when Prism::RegularExpressionNode
          build_node(:regexp, [build_node(:str, [node.unescaped], node, source, buffer_name), build_node(:regopt, regexp_options(node), node, source, buffer_name)], node, source, buffer_name)
        when Prism::InterpolatedRegularExpressionNode
          build_node(:regexp, node.parts.filter_map { |part| adapt(part, source, buffer_name) } + [build_node(:regopt, regexp_options(node), node, source, buffer_name)], node, source, buffer_name)
        when Prism::ArrayNode
          build_node(:array, node.elements.map { |child| adapt(child, source, buffer_name) }, node, source, buffer_name)
        when Prism::HashNode
          build_node(:hash, node.elements.map { |child| adapt(child, source, buffer_name) }, node, source, buffer_name)
        when Prism::KeywordHashNode
          build_node(:hash, node.elements.map { |child| adapt(child, source, buffer_name) }, node, source, buffer_name)
        when Prism::AssocNode
          build_node(:pair, [adapt(node.key, source, buffer_name), adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::SelfNode
          build_node(:self, [], node, source, buffer_name)
        when Prism::RedoNode
          build_node(:redo, [], node, source, buffer_name)
        when Prism::RetryNode
          build_node(:retry, [], node, source, buffer_name)
        when Prism::PreExecutionNode
          build_node(:preexe, [adapt_statements(node.statements, source, buffer_name)], node, source, buffer_name)
        when Prism::PostExecutionNode
          build_node(:postexe, [adapt_statements(node.statements, source, buffer_name)], node, source, buffer_name)
        when Prism::NumberedReferenceReadNode
          build_node(:nth_ref, [node.number], node, source, buffer_name)
        when Prism::BackReferenceReadNode
          build_node(:back_ref, [node.name], node, source, buffer_name)
        when Prism::LocalVariableReadNode
          build_node(:lvar, [node.name], node, source, buffer_name)
        when Prism::LocalVariableTargetNode
          build_node(:lvasgn, [node.name], node, source, buffer_name)
        when Prism::InstanceVariableReadNode
          build_node(:ivar, [node.name], node, source, buffer_name)
        when Prism::GlobalVariableReadNode
          build_node(:gvar, [node.name], node, source, buffer_name)
        when Prism::InstanceVariableWriteNode, Prism::InstanceVariableOrWriteNode
          build_node(:ivasgn, [node.name, adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::GlobalVariableWriteNode
          build_node(:gvasgn, [node.name, adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::LocalVariableWriteNode, Prism::LocalVariableOrWriteNode
          build_node(:lvasgn, [node.name, adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::LocalVariableOperatorWriteNode
          build_node(:op_asgn, [build_node(:lvasgn, [node.name], node, source, buffer_name), node.operator, adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::LocalVariableAndWriteNode
          build_node(:and_asgn, [build_node(:lvasgn, [node.name], node, source, buffer_name), adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::InstanceVariableOperatorWriteNode
          build_node(:op_asgn, [build_node(:ivasgn, [node.name], node, source, buffer_name), node.operator, adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::InstanceVariableAndWriteNode
          build_node(:and_asgn, [build_node(:ivasgn, [node.name], node, source, buffer_name), adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::ClassVariableWriteNode
          build_node(:cvasgn, [node.name, adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::ClassVariableReadNode
          build_node(:cvar, [node.name], node, source, buffer_name)
        when Prism::CallAndWriteNode
          build_node(:and_asgn, [adapt(node.target, source, buffer_name), adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::CallOperatorWriteNode
          build_node(:op_asgn, [adapt(node.target, source, buffer_name), node.operator, adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::IndexAndWriteNode
          build_node(:and_asgn, [adapt(node.target, source, buffer_name), adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::IndexOperatorWriteNode
          build_node(:op_asgn, [adapt(node.target, source, buffer_name), node.operator, adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::MatchWriteNode
          build_node(:match_with_lvasgn, [adapt(node.call, source, buffer_name), node.targets.map { |t| adapt(t, source, buffer_name) }], node, source, buffer_name)
        when Prism::MatchLastLineNode
          build_node(:match_current_line, [node.location.slice], node, source, buffer_name)
        when Prism::IntegerNode
          build_node(:int, [node.value], node, source, buffer_name)
        when Prism::FloatNode
          build_node(:float, [node.value], node, source, buffer_name)
        when Prism::RationalNode
          build_node(:rational, [node.value], node, source, buffer_name)
        when Prism::ImaginaryNode
          build_node(:complex, [node.value], node, source, buffer_name)
        when Prism::TrueNode
          build_node(:true, [], node, source, buffer_name)
        when Prism::FalseNode
          build_node(:false, [], node, source, buffer_name)
        when Prism::NilNode
          build_node(:nil, [], node, source, buffer_name)
        when Prism::AndNode
          build_node(:and, [adapt(node.left, source, buffer_name), adapt(node.right, source, buffer_name)], node, source, buffer_name)
        when Prism::OrNode
          build_node(:or, [adapt(node.left, source, buffer_name), adapt(node.right, source, buffer_name)], node, source, buffer_name)
        when Prism::IfNode
          build_node(:if, [adapt(node.predicate, source, buffer_name), adapt(node.statements, source, buffer_name), adapt(node.consequent, source, buffer_name)], node, source, buffer_name)
        when Prism::UnlessNode
          build_node(:if, [adapt(node.predicate, source, buffer_name), adapt(node.consequent, source, buffer_name), adapt(node.statements, source, buffer_name)], node, source, buffer_name)
        when Prism::WhileNode
          build_node(:while, [adapt(node.predicate, source, buffer_name), adapt(node.statements, source, buffer_name)], node, source, buffer_name)
        when Prism::UntilNode
          build_node(:until, [adapt(node.predicate, source, buffer_name), adapt(node.statements, source, buffer_name)], node, source, buffer_name)
        when Prism::ForNode
          build_node(:for, [adapt(node.index, source, buffer_name), adapt(node.collection, source, buffer_name), adapt(node.statements, source, buffer_name)], node, source, buffer_name)
        when Prism::MultiWriteNode
          mlhs_children = node.lefts.map { |left| adapt(left, source, buffer_name) }
          mlhs_children << adapt(node.rest, source, buffer_name) if node.rest
          mlhs_children.concat(node.rights.map { |right| adapt(right, source, buffer_name) }) if node.respond_to?(:rights)
          build_node(:masgn, [build_node(:mlhs, mlhs_children, node, source, buffer_name), adapt(node.value, source, buffer_name)], node, source, buffer_name)
        when Prism::RescueModifierNode
          build_node(:rescue, [adapt(node.expression, source, buffer_name), build_node(:resbody, [nil, nil, adapt(node.rescue_expression, source, buffer_name)], node, source, buffer_name), nil], node, source, buffer_name)
        when Prism::CaseNode
          children = [adapt(node.predicate, source, buffer_name)]
          children.concat(node.conditions.map { |condition| adapt(condition, source, buffer_name) })
          children << adapt(node.consequent, source, buffer_name) if node.consequent
          build_node(:case, children, node, source, buffer_name)
        when Prism::HashPatternNode
          build_node(:hash, node.elements.map { |child| adapt(child, source, buffer_name) }, node, source, buffer_name)
        when Prism::WhenNode
          condition =
            if node.conditions.length == 1
              adapt(node.conditions.first, source, buffer_name)
            else
              build_node(:array, node.conditions.map { |child| adapt(child, source, buffer_name) }, node, source, buffer_name)
            end
          build_node(:when, [condition, adapt(node.statements, source, buffer_name)].compact, node, source, buffer_name)
        when Prism::BeginNode
          rescue_bodies = node.rescue_clause ? adapt_rescue_clause(node.rescue_clause, source, buffer_name) : []
          ensure_body = node.ensure_clause ? adapt(node.ensure_clause.statements, source, buffer_name) : nil
          res = adapt(node.statements, source, buffer_name)
          res = build_node(:kwbegin, [res], node, source, buffer_name) if node.location.slice.start_with?('begin')
          if rescue_bodies.any? || ensure_body
            build_node(:ensure, [build_node(:rescue, [res, *rescue_bodies, nil], node, source, buffer_name), ensure_body], node, source, buffer_name)
          else
            res
          end
        when Prism::RescueNode
          adapt_rescue_clause(node, source, buffer_name)
        when Prism::EnsureNode
          adapt(node.statements, source, buffer_name)
        when Prism::LambdaNode
          build_node(:block, [build_node(:send, [nil, :lambda], node, source, buffer_name), adapt_block_parameters(node.parameters, source, buffer_name), adapt(node.body, source, buffer_name)], node, source, buffer_name)
        end
      end

      def adapt_statements(node, source, buffer_name)
        children = node.body.filter_map { |child| adapt(child, source, buffer_name) }
        return nil if children.empty?
        return children.first if children.one?

        build_node(:begin, children, node, source, buffer_name)
      end

      def adapt_parameters(node, source, buffer_name)
        return build_node(:args, [], nil, source, buffer_name) unless node

        children = []
        children.concat(node.requireds.map { |child| adapt_required_parameter(child, source, buffer_name) }) if node.respond_to?(:requireds)
        children.concat(node.optionals.map { |child| build_node(:optarg, [parameter_name(child), adapt(child.value, source, buffer_name)], child, source, buffer_name) }) if node.respond_to?(:optionals)
        children << build_node(:restarg, [parameter_name(node.rest)], node.rest, source, buffer_name) if node.respond_to?(:rest) && node.rest
        children.concat(node.posts.map { |child| adapt_required_parameter(child, source, buffer_name) }) if node.respond_to?(:posts)
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

      def adapt_required_parameter(child, source, buffer_name)
        if child.is_a?(Prism::MultiTargetNode)
          mlhs_children = child.lefts.map { |c| adapt_required_parameter(c, source, buffer_name) }
          mlhs_children << build_node(:restarg, [parameter_name(child.rest)], child.rest, source, buffer_name) if child.respond_to?(:rest) && child.rest
          mlhs_children.concat(child.rights.map { |c| adapt_required_parameter(c, source, buffer_name) }) if child.respond_to?(:rights)
          build_node(:mlhs, mlhs_children, child, source, buffer_name)
        else
          build_node(:arg, [parameter_name(child)], child, source, buffer_name)
        end
      end

      def adapt_keyword_parameter(node, source, buffer_name)
        case node
        when Prism::RequiredKeywordParameterNode
          build_node(:kwarg, [parameter_name(node)], node, source, buffer_name)
        when Prism::OptionalKeywordParameterNode
          build_node(:kwoptarg, [parameter_name(node), adapt(node.value, source, buffer_name)], node, source, buffer_name)
        else
          build_node(:arg, [parameter_name(node)], node, source, buffer_name)
        end
      end

      def adapt_call_node(node, source, buffer_name)
        children = [adapt(node.receiver, source, buffer_name), node.name]
        children.concat(node.arguments&.arguments.to_a.map { |arg| adapt(arg, source, buffer_name) } || [])
        children << adapt(node.block, source, buffer_name) if node.respond_to?(:block) && node.block && !node.block.is_a?(Prism::BlockNode)
        return build_node(:send, children, node, source, buffer_name) unless node.respond_to?(:block) && node.block.is_a?(Prism::BlockNode)

        end_offset = node.block.location.start_offset
        while end_offset > node.location.start_offset && source.byteslice(end_offset - 1, 1)&.match?(/\s/)
          end_offset -= 1
        end

        loc = Location.new(
          buffer_name,
          source,
          node.location.start_offset,
          end_offset,
          prism_node: node
        )
        send_node = Node.new(:send, children: children, loc: loc)
        loc.node = send_node
        send_node
      end

      def regexp_options(node)
        options = []
        options << :i if node.ignore_case?
        options << :m if node.multi_line?
        options << :x if node.extended?
        options
      end

      def parameter_name(node)
        node.respond_to?(:name) ? node.name : nil
      end

      def build_const_path(node, source, buffer_name)
        parent =
          if node.parent
            adapt(node.parent, source, buffer_name)
          elsif node.delimiter_loc
            build_node(:cbase, [], nil, source, buffer_name)
          end
        name = node.respond_to?(:name) ? node.name : node.child.name
        build_node(:const, [parent, name], node, source, buffer_name)
      end

      def build_node(type, children, prism_node, source, buffer_name)
        loc =
          if prism_node
            Location.new(buffer_name, source, prism_node.location.start_offset, prism_node.location.end_offset, prism_node: prism_node)
          else
            Location.new(buffer_name, source, 0, 0)
          end
        node = Node.new(type, children, location: loc)
        loc.node = node
        node
      end

      def adapt_rescue_clause(node, source, buffer_name)
        resbodies = []
        current = node
        while current
          exceptions = current.exceptions.map { |e| adapt(e, source, buffer_name) }
          exception_variable = adapt(current.reference, source, buffer_name)
          resbodies << build_node(:resbody, [build_node(:array, exceptions, current, source, buffer_name), exception_variable, adapt(current.statements, source, buffer_name)], current, source, buffer_name)
          current = current.consequent
        end
        resbodies
      end
    end
  end
end
