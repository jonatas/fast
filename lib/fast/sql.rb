# frozen_string_literal: true

require 'pg_query'
require_relative 'sql/rewriter'

module Fast
  module_function

  # Shortcut to parse a sql file
  # @example Fast.parse_sql_file('spec/fixtures/sql/select.sql')
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
  def parse_sql(statement, buffer_name: '(sql)')
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
      def first(pattern)
        search(pattern).first
      end

      def replace(pattern, with = nil, &replacement)
        replacement ||= ->(n) { replace(n.loc.expression, with) }
        if root?
          SQL.replace(pattern, self, &replacement)
        else
          parent.replace(pattern, &replacement)
        end
      end

      def token
        tokens.find { |e| e.start == location.begin }
      end

      def tokens
        location.expression.source_buffer.tokens
      end
    end

    module_function

    EMPTY_VALUES = [{}, [], '', :SETOP_NONE, :LIMIT_OPTION_DEFAULT, false].freeze

    # Parses SQL statements Using PGQuery
    # @see sql_to_h
    def parse(statement, buffer_name: '(sql)')
      return [] if statement.nil?

      source_buffer = SQL::SourceBuffer.new(buffer_name, source: statement)
      tree = PgQuery.parse(statement).tree
      parse_statements(tree, source_buffer)
    end

    def parse_statements(tree, source_buffer)
      _first, *, last_token = source_buffer.tokens
      stmts = tree.stmts.map do |stmt|
        parse_single_statement(stmt, source_buffer, last_token)
      end.flatten
      stmts.one? ? stmts.first : stmts
    end

    def parse_single_statement(stmt, source_buffer, last_token)
      from = stmt.stmt_location
      to = calculate_statement_end(stmt, from, last_token)
      expression = Parser::Source::Range.new(source_buffer, from, to)
      source_map = Parser::Source::Map.new(expression)
      sql_tree_to_ast(clean_structure(stmt.stmt.to_h), source_buffer: source_buffer, source_map: source_map)
    end

    def calculate_statement_end(stmt, from, last_token)
      stmt.stmt_len.zero? ? last_token.end : from + stmt.stmt_len
    end

    # Clean up the hash structure returned by PGQuery
    # @arg [Hash] hash the hash representation of the sql statement
    # @return [Hash] the hash representation of the sql statement
    def clean_structure(stmt)
      res_hash = stmt.map do |key, value|
        value = clean_structure(value) if value.is_a?(Hash)
        value = value.map { |v| clean_structure(v) } if value.is_a?(Array)
        value = nil if EMPTY_VALUES.include?(value)
        key = key.to_s.tr('-', '_').to_sym
        [key, value]
      end
      res_hash.to_h.compact
    end

    # Transform a sql tree into an AST.
    # Populates the location of the AST nodes with the source map.
    # @arg [Hash] obj the hash representation of the sql statement
    # @return [Array] the AST representation of the sql statement
    def sql_tree_to_ast(obj, source_buffer: nil, source_map: nil)
      recursive = ->(e) { sql_tree_to_ast(e, source_buffer: source_buffer, source_map: source_map.dup) }
      case obj
      when Array
        handle_array_ast(obj, recursive)
      when Hash
        handle_hash_ast(obj, source_buffer, source_map, recursive)
      else
        obj
      end
    end

    def handle_array_ast(obj, recursive)
      obj.map(&recursive).flatten.compact
    end

    def handle_hash_ast(obj, source_buffer, source_map, recursive)
      source_map = update_source_map(obj, source_buffer, source_map)
      obj.filter_map do |key, value|
        children = [*recursive.call(value)]
        Node.new(key, children, location: source_map)
      end
    end

    def update_source_map(obj, source_buffer, source_map)
      if (start = obj.delete(:location)) && (token = find_token_at_position(source_buffer, start))
        expression = Parser::Source::Range.new(source_buffer, token.start, token.end)
        Parser::Source::Map.new(expression)
      else
        source_map
      end
    end

    def find_token_at_position(source_buffer, start)
      source_buffer.tokens.find { |e| e.start == start }
    end
  end
end
