require 'pg_query'

module Fast
  module_function
  def parse_sql(statement)
    ast = PgQuery.parse(statement)
    threes = ast.tree.stmts.map(&:stmt).map do |stmt|
      Fast::Node.from_sql_statement(stmt)
    end
    
    threes
  end
end
