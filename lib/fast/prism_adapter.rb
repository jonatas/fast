# frozen_string_literal: true

require 'prism'

module Fast
  # Adapts Prism AST to Fast AST
  module PrismAdapter
    # Location allows to track the source code range from the Prism location
    class Location < Fast::Source::Range
      attr_accessor :node

      def initialize(source_buffer, start_offset, end_offset, prism_node: nil)
        @prism_node = prism_node
        super(
          source_buffer,
          character_offset(source_buffer.source, start_offset),
          character_offset(source_buffer.source, end_offset)
        )
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
          character_offset(source_buffer.source, prism_location.start_offset),
          character_offset(source_buffer.source, prism_location.end_offset)
        )
      end

      def character_offset(source, byte_offset)
        source.byteslice(0, byte_offset).size
      end
    end

    class << self
      def parse(source, buffer_name: '(string)')
        result = Prism.parse(source)
        unless result.success?
          puts "PRISM ERRORS: #{result.errors.map(&:message).join(', ')}"
          return
        end

        source_buffer = Fast::Source::Buffer.new(buffer_name, source: source)
        adapt(result.value, source_buffer)
      end

      def adapt(node, source_buffer)
        return if node.nil?

        case node
        when Symbol
          build_node(:sym, [node.to_s], nil, source_buffer)
        when String
          build_node(:str, [node], nil, source_buffer)
        when Prism::ProgramNode
          statements = adapt_statements(node.statements, source_buffer)
          statements.is_a?(Node) ? statements : build_node(:begin, statements, node, source_buffer)
        when Prism::StatementsNode
          adapt_statements(node, source_buffer)
        when Prism::AliasMethodNode, Prism::AliasGlobalVariableNode
          build_node(:alias, [adapt(node.new_name, source_buffer), adapt(node.old_name, source_buffer)], node, source_buffer)
        when Prism::DefinedNode
          build_node(:defined?, [adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::UndefNode
          build_node(:undef, node.names.map { |name| adapt(name, source_buffer) }, node, source_buffer)
        when Prism::ModuleNode
          build_node(:module, [adapt(node.constant_path, source_buffer), adapt(node.body, source_buffer)], node, source_buffer)
        when Prism::ClassNode
          build_node(:class, [adapt(node.constant_path, source_buffer), adapt(node.superclass, source_buffer), adapt(node.body, source_buffer)], node, source_buffer)
        when Prism::SingletonClassNode
          build_node(:sclass, [adapt(node.expression, source_buffer), adapt(node.body, source_buffer)], node, source_buffer)
        when Prism::DefNode
          if node.receiver
            build_node(:defs, [adapt(node.receiver, source_buffer), node.name, adapt_parameters(node.parameters, source_buffer), adapt(node.body, source_buffer)], node, source_buffer)
          else
            build_node(:def, [node.name, adapt_parameters(node.parameters, source_buffer), adapt(node.body, source_buffer)], node, source_buffer)
          end
        when Prism::BlockNode
          return nil unless node.respond_to?(:call)

          build_node(:block, [adapt_call_node(node.call, source_buffer), adapt_block_parameters(node.parameters, source_buffer), adapt(node.body, source_buffer)], node, source_buffer)
        when Prism::CallNode
          if node.respond_to?(:block) && node.block.is_a?(Prism::BlockNode)
            return build_node(
              :block,
              [
                adapt_call_node(node, source_buffer),
                adapt_block_parameters(node.block.parameters, source_buffer),
                adapt(node.block.body, source_buffer)
              ],
              node,
              source_buffer
            )
          end

          adapt_call_node(node, source_buffer)
        when Prism::ParenthesesNode
          adapt(node.body, source_buffer)
        when Prism::RangeNode
          build_node(node.exclude_end? ? :erange : :irange, [adapt(node.left, source_buffer), adapt(node.right, source_buffer)], node, source_buffer)
        when Prism::BlockArgumentNode
          build_node(:block_pass, [adapt(node.expression, source_buffer)], node, source_buffer)
        when Prism::ReturnNode
          build_node(:return, node.arguments&.arguments.to_a.map { |arg| adapt(arg, source_buffer) }, node, source_buffer)
        when Prism::NextNode
          build_node(:next, node.arguments&.arguments.to_a.map { |arg| adapt(arg, source_buffer) }, node, source_buffer)
        when Prism::BreakNode
          build_node(:break, node.arguments&.arguments.to_a.map { |arg| adapt(arg, source_buffer) }, node, source_buffer)
        when Prism::YieldNode
          build_node(:yield, node.arguments&.arguments.to_a.map { |arg| adapt(arg, source_buffer) }, node, source_buffer)
        when Prism::SuperNode
          build_node(:super, node.arguments&.arguments.to_a.map { |arg| adapt(arg, source_buffer) }, node, source_buffer)
        when Prism::ForwardingSuperNode
          build_node(:zsuper, [], node, source_buffer)
        when Prism::SplatNode
          build_node(:splat, [adapt(node.expression, source_buffer)], node, source_buffer)
        when Prism::AssocSplatNode
          build_node(:kwsplat, [adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::ConstantPathNode
          build_const_path(node, source_buffer)

        when Prism::ConstantReadNode
          build_node(:const, [nil, node.name], node, source_buffer)
        when Prism::ConstantWriteNode
          build_node(:casgn, [nil, node.name, adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::ConstantPathWriteNode
          build_node(:casgn, [adapt(node.target, source_buffer), nil, adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::SymbolNode
          build_node(:sym, [node.unescaped], node, source_buffer)
        when Prism::StringNode
          build_node(:str, [node.unescaped], node, source_buffer)
        when Prism::XStringNode
          build_node(:xstr, [node.unescaped], node, source_buffer)
        when Prism::InterpolatedStringNode
          build_node(:dstr, node.parts.filter_map { |part| adapt(part, source_buffer) }, node, source_buffer)
        when Prism::InterpolatedXStringNode
          build_node(:dxstr, node.parts.filter_map { |part| adapt(part, source_buffer) }, node, source_buffer)
        when Prism::EmbeddedStatementsNode
          build_node(:begin, [adapt(node.statements, source_buffer)], node, source_buffer)
        when Prism::InterpolatedSymbolNode
          build_node(:dsym, node.parts.filter_map { |part| adapt(part, source_buffer) }, node, source_buffer)
        when Prism::RegularExpressionNode
          build_node(:regexp, [build_node(:str, [node.unescaped], node, source_buffer), build_node(:regopt, regexp_options(node), node, source_buffer)], node, source_buffer)
        when Prism::InterpolatedRegularExpressionNode
          build_node(:regexp, node.parts.filter_map { |part| adapt(part, source_buffer) } + [build_node(:regopt, regexp_options(node), node, source_buffer)], node, source_buffer)
        when Prism::ArrayNode
          build_node(:array, node.elements.map { |child| adapt(child, source_buffer) }, node, source_buffer)
        when Prism::HashNode
          build_node(:hash, node.elements.map { |child| adapt(child, source_buffer) }, node, source_buffer)
        when Prism::KeywordHashNode
          build_node(:hash, node.elements.map { |child| adapt(child, source_buffer) }, node, source_buffer)
        when Prism::AssocNode
          build_node(:pair, [adapt(node.key, source_buffer), adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::SelfNode
          build_node(:self, [], node, source_buffer)
        when Prism::RedoNode
          build_node(:redo, [], node, source_buffer)
        when Prism::RetryNode
          build_node(:retry, [], node, source_buffer)
        when Prism::PreExecutionNode
          build_node(:preexe, [adapt_statements(node.statements, source_buffer)], node, source_buffer)
        when Prism::PostExecutionNode
          build_node(:postexe, [adapt_statements(node.statements, source_buffer)], node, source_buffer)
        when Prism::NumberedReferenceReadNode
          build_node(:nth_ref, [node.number], node, source_buffer)
        when Prism::BackReferenceReadNode
          build_node(:back_ref, [node.name], node, source_buffer)
        when Prism::LocalVariableReadNode
          build_node(:lvar, [node.name], node, source_buffer)
        when Prism::LocalVariableTargetNode
          build_node(:lvasgn, [node.name], node, source_buffer)
        when Prism::InstanceVariableReadNode
          build_node(:ivar, [node.name], node, source_buffer)
        when Prism::GlobalVariableReadNode
          build_node(:gvar, [node.name], node, source_buffer)
        when Prism::InstanceVariableWriteNode, Prism::InstanceVariableOrWriteNode
          build_node(:ivasgn, [node.name, adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::GlobalVariableWriteNode
          build_node(:gvasgn, [node.name, adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::LocalVariableWriteNode, Prism::LocalVariableOrWriteNode
          build_node(:lvasgn, [node.name, adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::LocalVariableOperatorWriteNode
          build_node(:op_asgn, [build_node(:lvasgn, [node.name], node, source_buffer), node.binary_operator, adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::LocalVariableAndWriteNode
          build_node(:and_asgn, [build_node(:lvasgn, [node.name], node, source_buffer), adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::InstanceVariableOperatorWriteNode
          build_node(:op_asgn, [build_node(:ivasgn, [node.name], node, source_buffer), node.binary_operator, adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::InstanceVariableAndWriteNode
          build_node(:and_asgn, [build_node(:ivasgn, [node.name], node, source_buffer), adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::ClassVariableWriteNode
          build_node(:cvasgn, [node.name, adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::ClassVariableReadNode
          build_node(:cvar, [node.name], node, source_buffer)
        when Prism::CallAndWriteNode
          build_node(:and_asgn, [adapt(node.target, source_buffer), adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::CallOperatorWriteNode
          build_node(:op_asgn, [adapt(node.target, source_buffer), node.binary_operator, adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::IndexAndWriteNode
          build_node(:and_asgn, [adapt(node.target, source_buffer), adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::IndexOperatorWriteNode
          build_node(:op_asgn, [adapt(node.target, source_buffer), node.binary_operator, adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::MatchWriteNode
          build_node(:match_with_lvasgn, [adapt(node.call, source_buffer), node.targets.map { |t| adapt(t, source_buffer) }], node, source_buffer)
        when Prism::MatchLastLineNode
          build_node(:match_current_line, [node.location.slice], node, source_buffer)
        when Prism::IntegerNode
          build_node(:int, [node.value], node, source_buffer)
        when Prism::FloatNode
          build_node(:float, [node.value], node, source_buffer)
        when Prism::RationalNode
          build_node(:rational, [node.value], node, source_buffer)
        when Prism::ImaginaryNode
          build_node(:complex, [node.value], node, source_buffer)
        when Prism::TrueNode
          build_node(:true, [], node, source_buffer)
        when Prism::FalseNode
          build_node(:false, [], node, source_buffer)
        when Prism::NilNode
          build_node(:nil, [], node, source_buffer)
        when Prism::AndNode
          build_node(:and, [adapt(node.left, source_buffer), adapt(node.right, source_buffer)], node, source_buffer)
        when Prism::OrNode
          build_node(:or, [adapt(node.left, source_buffer), adapt(node.right, source_buffer)], node, source_buffer)
        when Prism::IfNode
          build_node(:if, [adapt(node.predicate, source_buffer), adapt(node.statements, source_buffer), adapt(node.consequent, source_buffer)], node, source_buffer)
        when Prism::UnlessNode
          build_node(:if, [adapt(node.predicate, source_buffer), adapt(node.consequent, source_buffer), adapt(node.statements, source_buffer)], node, source_buffer)
        when Prism::WhileNode
          build_node(:while, [adapt(node.predicate, source_buffer), adapt(node.statements, source_buffer)], node, source_buffer)
        when Prism::UntilNode
          build_node(:until, [adapt(node.predicate, source_buffer), adapt(node.statements, source_buffer)], node, source_buffer)
        when Prism::ForNode
          build_node(:for, [adapt(node.index, source_buffer), adapt(node.collection, source_buffer), adapt(node.statements, source_buffer)], node, source_buffer)
        when Prism::MultiWriteNode
          mlhs_children = node.lefts.map { |left| adapt(left, source_buffer) }
          mlhs_children << adapt(node.rest, source_buffer) if node.rest
          mlhs_children.concat(node.rights.map { |right| adapt(right, source_buffer) }) if node.respond_to?(:rights)
          build_node(:masgn, [build_node(:mlhs, mlhs_children, node, source_buffer), adapt(node.value, source_buffer)], node, source_buffer)
        when Prism::RescueModifierNode
          build_node(:rescue, [adapt(node.expression, source_buffer), build_node(:resbody, [nil, nil, adapt(node.rescue_expression, source_buffer)], node, source_buffer), nil], node, source_buffer)
        when Prism::CaseNode
          children = [adapt(node.predicate, source_buffer)]
          children.concat(node.conditions.map { |condition| adapt(condition, source_buffer) })
          children << adapt(node.consequent, source_buffer) if node.consequent
          build_node(:case, children, node, source_buffer)
        when Prism::HashPatternNode
          build_node(:hash, node.elements.map { |child| adapt(child, source_buffer) }, node, source_buffer)
        when Prism::WhenNode
          condition =
            if node.conditions.length == 1
              adapt(node.conditions.first, source_buffer)
            else
              build_node(:array, node.conditions.map { |child| adapt(child, source_buffer) }, node, source_buffer)
            end
          build_node(:when, [condition, adapt(node.statements, source_buffer)].compact, node, source_buffer)
        when Prism::BeginNode
          rescue_bodies = node.rescue_clause ? adapt_rescue_clause(node.rescue_clause, source_buffer) : []
          ensure_body = node.ensure_clause ? adapt(node.ensure_clause.statements, source_buffer) : nil
          res = adapt(node.statements, source_buffer)
          res = build_node(:kwbegin, [res], node, source_buffer) if node.location.slice.start_with?('begin')
          if rescue_bodies.any? || ensure_body
            build_node(:ensure, [build_node(:rescue, [res, *rescue_bodies, nil], node, source_buffer), ensure_body], node, source_buffer)
          else
            res
          end
        when Prism::RescueNode
          adapt_rescue_clause(node, source_buffer)
        when Prism::EnsureNode
          adapt(node.statements, source_buffer)
        when Prism::LambdaNode
          build_node(:block, [build_node(:send, [nil, :lambda], node, source_buffer), adapt_block_parameters(node.parameters, source_buffer), adapt(node.body, source_buffer)], node, source_buffer)
        end
      end

      def adapt_statements(node, source_buffer)
        children = node.body.filter_map { |child| adapt(child, source_buffer) }
        return nil if children.empty?
        return children.first if children.one?

        build_node(:begin, children, node, source_buffer)
      end

      def adapt_parameters(node, source_buffer)
        return build_node(:args, [], nil, source_buffer) unless node

        children = []
        children.concat(node.requireds.map { |child| adapt_required_parameter(child, source_buffer) }) if node.respond_to?(:requireds)
        children.concat(node.optionals.map { |child| build_node(:optarg, [parameter_name(child), adapt(child.value, source_buffer)], child, source_buffer) }) if node.respond_to?(:optionals)
        children << build_node(:restarg, [parameter_name(node.rest)], node.rest, source_buffer) if node.respond_to?(:rest) && node.rest
        children.concat(node.posts.map { |child| adapt_required_parameter(child, source_buffer) }) if node.respond_to?(:posts)
        children.concat(node.keywords.map { |child| adapt_keyword_parameter(child, source_buffer) }) if node.respond_to?(:keywords)
        children << build_node(:kwrestarg, [parameter_name(node.keyword_rest)], node.keyword_rest, source_buffer) if node.respond_to?(:keyword_rest) && node.keyword_rest
        children << build_node(:blockarg, [parameter_name(node.block)], node.block, source_buffer) if node.respond_to?(:block) && node.block
        build_node(:args, children, node, source_buffer)
      end

      def adapt_block_parameters(node, source_buffer)
        return build_node(:args, [], nil, source_buffer) unless node

        params = node.respond_to?(:parameters) ? node.parameters : node
        adapt_parameters(params, source_buffer)
      end

      def adapt_required_parameter(child, source_buffer)
        if child.is_a?(Prism::MultiTargetNode)
          mlhs_children = child.lefts.map { |c| adapt_required_parameter(c, source_buffer) }
          mlhs_children << build_node(:restarg, [parameter_name(child.rest)], child.rest, source_buffer) if child.respond_to?(:rest) && child.rest
          mlhs_children.concat(child.rights.map { |c| adapt_required_parameter(c, source_buffer) }) if child.respond_to?(:rights)
          build_node(:mlhs, mlhs_children, child, source_buffer)
        else
          build_node(:arg, [parameter_name(child)], child, source_buffer)
        end
      end

      def adapt_keyword_parameter(node, source_buffer)
        case node
        when Prism::RequiredKeywordParameterNode
          build_node(:kwarg, [parameter_name(node)], node, source_buffer)
        when Prism::OptionalKeywordParameterNode
          build_node(:kwoptarg, [parameter_name(node), adapt(node.value, source_buffer)], node, source_buffer)
        else
          build_node(:arg, [parameter_name(node)], node, source_buffer)
        end
      end

      def adapt_call_node(node, source_buffer)
        children = [adapt(node.receiver, source_buffer), node.name]
        children.concat(node.arguments&.arguments.to_a.map { |arg| adapt(arg, source_buffer) } || [])
        children << adapt(node.block, source_buffer) if node.respond_to?(:block) && node.block && !node.block.is_a?(Prism::BlockNode)
        return build_node(:send, children, node, source_buffer) unless node.respond_to?(:block) && node.block.is_a?(Prism::BlockNode)

        end_offset = node.block.location.start_offset
        while end_offset > node.location.start_offset && source_buffer.source.byteslice(end_offset - 1, 1)&.match?(/\s/)
          end_offset -= 1
        end

        loc = Location.new(
          source_buffer,
          node.location.start_offset,
          end_offset,
          prism_node: node
        )
        send_node = Node.new(:send, children, location: loc)
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

      def build_const_path(node, source_buffer)
        parent =
          if node.parent
            adapt(node.parent, source_buffer)
          elsif node.delimiter_loc
            build_node(:cbase, [], nil, source_buffer)
          end
        name = node.respond_to?(:name) ? node.name : node.child.name
        build_node(:const, [parent, name], node, source_buffer)
      end

      def build_node(type, children, prism_node, source_buffer)
        loc =
          if prism_node
            Location.new(source_buffer, prism_node.location.start_offset, prism_node.location.end_offset, prism_node: prism_node)
          else
            Location.new(source_buffer, 0, 0)
          end
        node = Node.new(type, children, location: loc)
        loc.node = node
        node
      end

      def adapt_rescue_clause(node, source_buffer)
        resbodies = []
        current = node
        while current
          exceptions = current.exceptions.map { |e| adapt(e, source_buffer) }
          exception_variable = adapt(current.reference, source_buffer)
          resbodies << build_node(:resbody, [build_node(:array, exceptions, current, source_buffer), exception_variable, adapt(current.statements, source_buffer)], current, source_buffer)
          current = current.consequent
        end
        resbodies
      end
    end
  end
end
