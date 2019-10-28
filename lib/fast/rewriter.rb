# frozen_string_literal: true

# Rewriter loads a set of methods related to automated replacement using
# expressions and custom blocks of code.
module Fast
  class << self
    # Replaces content based on a pattern.
    # @param [Astrolabe::Node] ast with the current AST to search.
    # @param [String] pattern with the expression to be targeting nodes.
    # @param [Proc] replacement gives the [Rewriter] context in the block.
    # @example
    #   Fast.replace?(Fast.ast("a = 1"),"lvasgn") do |node|
    #     replace(node.location.name, 'variable_renamed')
    #   end # => variable_renamed = 1
    # @return [String] with the new source code after apply the replacement
    # @see Fast::Rewriter
    def replace(pattern, ast, source = nil, &replacement)
      rewriter_for(pattern, ast, source, &replacement).rewrite!
    end

    # @return [Fast::Rewriter]
    def rewriter_for(pattern, ast, source = nil, &replacement)
      rewriter = Rewriter.new
      rewriter.source = source
      rewriter.ast = ast
      rewriter.search = pattern
      rewriter.replacement = replacement
      rewriter
    end

    # Replaces the source of an {Fast#ast_from_file} with
    # and the same source if the pattern does not match.
    def replace_file(pattern, file, &replacement)
      ast = ast_from_file(file)
      replace(pattern, ast, IO.read(file), &replacement)
    end

    # Combines #replace_file output overriding the file if the output is different
    # from the original file content.
    def rewrite_file(pattern, file, &replacement)
      previous_content = IO.read(file)
      content = replace_file(pattern, file, &replacement)
      File.open(file, 'w+') { |f| f.puts content } if content != previous_content
    end
  end

  # Rewriter encapsulates {Rewriter#match_index} to allow
  # {ExperimentFile.partial_replace} in a {Fast::ExperimentFile}.
  # @see https://www.rubydoc.info/github/whitequark/parser/Parser/TreeRewriter
  # @note the standalone class needs to combines {Rewriter#replace_on} to properly generate the `on_<node-type>` methods depending on the expression being used.
  # @example Simple Rewriter
  #    rewriter = Rewriter.new buffer
  #    rewriter.ast = Fast.ast("a = 1")
  #    rewriter.search ='(lvasgn _ ...)'
  #    rewriter.replacement =  -> (node) { replace(node.location.name, 'variable_renamed') }
  #    rewriter.rewrite! # => "variable_renamed = 1"
  class Rewriter < Parser::TreeRewriter
    # @return [Integer] with occurrence index
    attr_reader :match_index
    attr_accessor :search, :replacement, :source, :ast
    def initialize(*_args)
      super()
      @match_index = 0
    end

    def rewrite!
      replace_on(*types)
      rewrite(buffer, ast)
    end

    def buffer
      buffer = Parser::Source::Buffer.new('replacement')
      buffer.source = source || ast.loc.expression.source
      buffer
    end

    # @return [Array<Symbol>] with all types that matches
    def types
      Fast.search(search, ast).grep(Parser::AST::Node).map(&:type).uniq
    end

    def match?(node)
      Fast.match?(search, node)
    end

    # Generate methods for all affected types.
    # @see Fast.replace
    def replace_on(*types)
      types.map do |type|
        self.class.send :define_method, "on_#{type}" do |node|
          if captures = match?(node) # rubocop:disable Lint/AssignmentInCondition
            @match_index += 1
            execute_replacement(node, captures)
          end
          super(node)
        end
      end
    end

    # Execute {#replacement} block
    # @param [Astrolabe::Node] node that will be yield in the replacement block
    # @param [Array<Object>, nil] captures are yield if {#replacement} take second argument.
    def execute_replacement(node, captures)
      if replacement.parameters.length == 1
        instance_exec node, &replacement
      else
        instance_exec node, captures, &replacement
      end
    end
  end
end
