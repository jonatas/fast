require 'pg_query'

module Fast
  module_function
  def parse_sql(statement)
    return [] if statement.nil?
    ast = PgQuery.parse(statement)
    threes = ast.tree.stmts.map(&:stmt).map do |stmt|
      from_sql_statement(stmt)
    end.flatten
    threes.one? ? threes.first : threes
  end

  def from_sql_statement(stmt, buffer_name: "sql")
    case stmt
    when PgQuery::ResTarget then
      tuple = 
        case stmt.val.node
        when :a_const
          stmt.val.a_const.val.to_h.compact
        when :a_array_expr
          stmt.val.send(stmt.val.node).elements.map do |e|
            from_sql_statement(e)
          end
        end

      return tuple.map do |k,v|
        case v
        when Hash, Array
          v = v.compact
          if v.one?
            v = v.values.first
          end
        end

        if k == :float
          v = v.to_f
        end
        require 'pry'
        binding.pry if v.nil?
        Node.new(k, [*v], buffer_name: buffer_name)
      end
    end
    case stmt.node
    when :select_stmt
      if (s=stmt.select_stmt)
        s.target_list.map{|t|from_sql_statement(t, buffer_name:  buffer_name)}.flatten
      end
    when :res_target
      children = 
        if (target=stmt.res_target)
          from_sql_statement(target, buffer_name:  buffer_name)
        end
      Node.new(:select, children, location: nil, buffer_name: buffer_name)
    when :a_const
      if v = stmt.a_const.val
        type = v.node
        Node.new(type, [v.public_send(type).ival], buffer_name: buffer_name)
      end
    else
      require "pry";binding.pry 
    end
  end
end
