module Fast
  module SQL
    class << self
      # @see Fast::SQLRewriter
      # @return string with the content updated in case the pattern matches.
      def replace(pattern, ast, &replacement)
        sql_rewriter_for(pattern, ast, &replacement).rewrite!
      end

      # @return [Fast::SQL::Rewriter]
      # @see Fast::Rewriter
      def sql_rewriter_for(pattern, ast, &replacement)
        rewriter = Rewriter.new
        rewriter.ast = ast
        rewriter.search = pattern
        rewriter.replacement = replacement
        rewriter
      end

      # @return true  file is updated
      def replace_file(pattern, file, &replacement)
        original = IO.read(file)
        ast = parse(original)
        content = replace(pattern, ast, &replacement)
        if content != original
          File.open(file, 'w+') { |f| f.print content }
        end
      end
    end

    # Extends fast rewriter to support SQL
    # @see Fast::Rewriter
    class Rewriter < Fast::Rewriter

      # @return [Array<Symbol>] with all types that matches
      def types
        [ast.type] + ast.search(search).grep(Parser::AST::Node).map(&:type).uniq
      end

      # Generate methods for all affected types.
      # @see Fast.replace
      def replace_on(*types)
        types.map do |type|
          self.instance_exec do
            self.class.define_method :"on_#{type}" do |node|
              if Fast.match?(search, node)
                @match_index += 1
                execute_replacement(node, captures)
              else
                # For some reason SQL nodes are not being automatically invoked,
                # so we need to match the root node and invoke replacement for all
                # matching elements.
                node.search(search).each_with_index do |node, i|
                  @match_index += 1
                  execute_replacement(node, nil)
                end
              end
              process_regular_node(node)
            end
          end
        end
      end
    end
  end
end
