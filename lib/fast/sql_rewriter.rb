
module Fast
  class << self
    # @see Fast::SQLRewriter
    def replace_sql(pattern, ast, source = nil, &replacement)
      sql_rewriter_for(pattern, ast, source, &replacement).rewrite!
    end

    # @return [Fast::Rewriter]
    def sql_rewriter_for(pattern, ast, source = nil, &replacement)
      rewriter = SQLRewriter.new
      rewriter.source = source
      rewriter.ast = ast
      rewriter.search = pattern
      rewriter.replacement = replacement
      rewriter
    end

    def replace_sql_file(pattern, file, &replacement)
      ast = parse_sql(file)
      replace(pattern, ast, IO.read(file), &replacement)
    end

    # Combines #replace_file output overriding the file if the output is different
    # from the original file content.
    def rewrite_sql_file(pattern, file, &replacement)
      previous_content = IO.read(file)
      content = replace_sql_file(pattern, file, &replacement)
      File.open(file, 'w+') { |f| f.puts content } if content != previous_content
    end
  end

  class SQLRewriter < Fast::Rewriter

    # @return [Array<Symbol>] with all types that matches
    def types
      [ast.type] + matching_nodes.grep(Parser::AST::Node).map(&:type).uniq
    end

    def matching_nodes
      @matching_nodes ||= ast.search(search)
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
