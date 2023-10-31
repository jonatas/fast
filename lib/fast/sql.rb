require 'pg_query'

module Fast
  module_function

  def parse_sql(statement)
    return [] if statement.nil?
    stmts = sql_to_h(statement).map do |v|
      sql_tree_to_ast(v)
    end.flatten
    stmts.one? ? stmts.first : stmts
  end

  # Transform a sql statement into a hash
  def sql_to_h(statement)
    tree = PgQuery.parse(statement).tree
    tree.to_h[:stmts].map{|e|clean_structure(e[:stmt])}
  end

  # Clean up the hash structure returned by PgQuery
  def clean_structure(hash)
    res_hash = hash.map do |key, value|
      value = clean_structure(value) if value.is_a?(Hash)
      value = value.map(&Fast.method(:clean_structure)) if value.is_a?(Array)
      value = nil if key.to_s =~ /_(location|len)$/ || key == :location
      value = nil if [{}, [], "", :SETOP_NONE, :LIMIT_OPTION_DEFAULT, false].include?(value)
      [key, value]
    end
    res_hash.to_h.compact
  end

  def sql_tree_to_ast(obj)
    case obj
    when Array
      obj.map(&Fast.method(:sql_tree_to_ast)).flatten.compact
    when Hash
      source_map = {}
      obj.map do |key, value|
        case key
        when /_(location|len)$/, :location
          source_map[key] = value
          next
        end
        n = Node.new(key, [*sql_tree_to_ast(value)], source_map)
        source_map = {}
        n
      end.compact
    else
      obj
    end
  end
end

