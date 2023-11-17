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

      # @return Fast::SQL::Node with the parsed content
      def parse_file(file)
        parse(IO.read(file), buffer_name: file)
      end

      # Replace a SQL file with the given pattern.
      # Use a replacement code block to change the content.
      # @return nil in case does not update the file
      # @return true in case the file is updated
      # @see Fast::SQL::Rewriter
      def replace_file(pattern, file, &replacement)
        original = IO.read(file)
        ast = parse_file(file)
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
        ast.type
      end

      # Generate methods for all affected types.
      # Note the strategy is different from parent class, it if matches the root node, it executes otherwise it search pattern on
      # all matching elements.
      # @see Fast.replace
      def replace_on(*types)
        types.map do |type|
          self.instance_exec do
            self.class.define_method :"on_#{ast.type}" do |node|
              # SQL nodes are not being automatically invoked by the rewriter,
              # so we need to match the root node and invoke on matching inner elements.
              node.search(search).each_with_index do |node, i|
                @match_index += 1
                execute_replacement(node, nil)
              end
            end
          end
        end
      end
    end
  end
end
