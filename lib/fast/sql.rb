require 'pg_query'

module Fast
  module_function

  def parse_sql(statement)
    return [] if statement.nil?
    stmts = sql_to_h(statement).values.map do |v|
      to_sql_ast(v)
    end
    stmts.one? ? stmts.first : stmts
  end

  # Transform a sql statement into a hash
  def sql_to_h(statement)
    tree = PgQuery.parse(statement).tree
    clean_structure(tree.to_h)
  end

  # Clean up the hash structure returned by PgQuery
  def clean_structure(hash)
    hash.delete(:version)
    res_hash = hash.map do |key, value|
      value = clean_structure(value) if value.is_a?(Hash)
      value = value.map(&Fast.method(:clean_structure)) if value.is_a?(Array)
      value = nil if [{}, [], "", :SETOP_NONE, :LIMIT_OPTION_DEFAULT, false].include?(value)
      [key, value]
    end
    res_hash.to_h.compact
  end

  def to_sql_ast(obj)
    case obj
    when Array
      obj.map(&Fast.method(:to_sql_ast))
    when Hash
      hash.map do |key, value|
        children = 
          case value
          when Hash
            hash[key] = to_sql_ast(value)
          end
        Node.new(key, *[children])
      end
    else
      obj
    end
  end
end
