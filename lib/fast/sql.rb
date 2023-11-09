require 'pg_query'
require_relative 'sql/rewriter'

module Fast

  module_function

  
  # @return [Fast::Node] the AST representation of the sql statements from a file
  def parse_sql_file(file)
    SQL.parse_file(file)
  end

  # @return [Fast::SQLRewriter] which can be used to rewrite the SQL
  # @see Fast::SQLRewriter
  def sql_rewriter_for(pattern, ast, &replacement)
    SQL.rewriter_for(pattern, ast, &replacement)
  end

  # @return string with the sql content updated in case the pattern matches.
  # @see Fast::SQLRewriter
  # @example
  # Fast.replace_sql('ival', Fast.parse_sql('select 1'), &->(node){ replace(node.location.expression, '2') }) # => "select 2"
  def replace_sql(pattern, ast, &replacement)
    SQL.replace(pattern, ast, &replacement)
  end

  # @return string with the sql content updated in case the pattern matches.
  def replace_sql_file(pattern, file, &replacement)
    SQL.replace_file(pattern, file, &replacement)
  end

  # @return [Fast::Node] the AST representation of the sql statement
  # @example
  # ast = Fast.parse_sql("select 'hello AST'")
  #  => s(:select_stmt,
  #       s(:target_list,
  #         s(:res_target,
  #           s(:val,
  #             s(:a_const,
  #               s(:val,
  #                 s(:string,
  #                   s(:str, "hello AST"))))))))
  # `s` represents a Fast::Node which is a subclass of Parser::AST::Node and
  # has additional methods to access the tokens and location of the node.
  # ast.search(:string).first.location.expression
  #  => #<Parser::Source::Range (sql) 7...18>
  def parse_sql(statement, buffer_name: "(sql)")
    SQL.parse(statement, buffer_name: buffer_name)
  end

  # This module contains methods to parse SQL statements and rewrite them.
  # It uses PGQuery to parse the SQL statements.
  # It uses Parser to rewrite the SQL statements.
  # It uses Parser::Source::Map to map the AST nodes to the SQL tokens.
  #
  # @example
  #  Fast::SQL.parse("select 1")
  #  => s(:select_stmt, s(:target_list, ...
  # @see Fast::SQL::Node
  module SQL
    # The SQL source buffer is a subclass of Parser::Source::Buffer
    # which contains the tokens of the SQL statement.
    # When you call `ast.location.expression` it will return a range
    # which is mapped to the tokens.
    # @example
    # ast = Fast::SQL.parse("select 1")
    # ast.location.expression # => #<Parser::Source::Range (sql) 0...9>
    # ast.location.expression.source_buffer.tokens
    # => [
    #   <PgQuery::ScanToken: start: 0, end: 6, token: :SELECT, keyword_kind: :RESERVED_KEYWORD>,
    #   <PgQuery::ScanToken: start: 7, end: 8, token: :ICONST, keyword_kind: :NO_KEYWORD>]
    # @see Fast::SQL::Node
    class SourceBuffer < Parser::Source::Buffer
      def tokens
        @tokens ||= PgQuery.scan(source).first.tokens
      end
    end

    # The SQL node is an AST node with additional tokenization info
    class Node < Fast::Node
      def token
        tokens.find{|e|e.start == location.begin}
      end

      def tokens
        location.expression.source_buffer.tokens
      end
    end

    module_function

    # Parses SQL statements Using PGQuery
    # @see sql_to_h
    def parse(statement, buffer_name: "(sql)")
      return [] if statement.nil?
      source_buffer = SQL::SourceBuffer.new(buffer_name, source: statement)
      first, *, last = source_buffer.tokens
      expression = Parser::Source::Range.new(source_buffer, first.start, last.end)
      source_map = Parser::Source::Map.new(expression)
      stmts = sql_to_h(statement).map do |v|
        sql_tree_to_ast(v, source_buffer: source_buffer, source_map: source_map)
      end.flatten
      stmts.one? ? stmts.first : stmts
    end

    # Transform a sql statement into a hash
    # Clean up the hash structure returned by PgQuery
    # @return [Hash] the hash representation of the sql statement
    def sql_to_h(statement)
      tree = PgQuery.parse(statement).tree
      tree.to_h[:stmts].map{|e|clean_structure(e[:stmt])}
    end

    # Clean up the hash structure returned by PgQuery
    # Skip location if not needed.
    # @arg [Hash] hash the hash representation of the sql statement
    # @arg [Boolean] include_location whether to include location or not
    # @return [Hash] the hash representation of the sql statement
    def clean_structure(hash, include_location: true)
      res_hash = hash.map do |key, value|
        value = clean_structure(value) if value.is_a?(Hash)
        value = value.map(&Fast::SQL.method(:clean_structure)) if value.is_a?(Array)
        unless include_location
          value = nil if key.to_s =~ /_(location|len)$/ || key == :location
        end
        value = nil if [{}, [], "", :SETOP_NONE, :LIMIT_OPTION_DEFAULT, false].include?(value)
        key = key.to_s.tr('-','_').to_sym
        [key, value]
      end
      res_hash.to_h.compact
    end

    # Transform a sql tree into an AST.
    # Populates the location of the AST nodes with the source map.
    # @arg [Hash] obj the hash representation of the sql statement
    # @return [Array] the AST representation of the sql statement
    def sql_tree_to_ast(obj, source_buffer: nil, source_map: nil)
      recursive = -> (e) { sql_tree_to_ast(e, source_buffer: source_buffer, source_map: source_map.dup) }
      case obj
      when Array
        obj.map(&recursive).flatten.compact
      when Hash
        if (start = obj.delete(:location))
          if (token = source_buffer.tokens.find{|e|e.start == start})
            expression = Parser::Source::Range.new(source_buffer, token.start, token.end)
            source_map = Parser::Source::Map.new(expression)
          end
        end
        obj.map do |key, value|
          children  = [*recursive.call(value)]
          Node.new(key, children, location: source_map)
        end.compact
      else
        obj
      end
    end
  end
end

