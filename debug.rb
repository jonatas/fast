require 'fast'
require 'fast/sql'

ast = Fast.parse_sql_file("cte_example.sql")
ctes = {}

Fast.search('(common_table_expr ...)', ast).each do |node|
  name_node = node.search('(ctename $_)').first
  query_wrapper = node.search('(ctequery $_)').first
  if name_node && query_wrapper
    name = name_node.children.first # extract string from sval
    ctes[name] = query_wrapper.children.first
  end
end

puts "Found CTEs: #{ctes.keys.join(', ')}"

sales_2023 = ctes['sales_2023']

all_selects = [ast, *ast.each_descendant].select { |n| n.respond_to?(:type) && n.type == :select_stmt }

all_selects.each do |node|
  if node != sales_2023
    sales_str = sales_2023.to_s.gsub(/\s+/, ' ')
    node_str = node.to_s.gsub(/\s+/, ' ')
    if sales_str[0..50] == node_str[0..50]
      puts "COMPARING WITH sales_2023:"
      puts "sales_2023:\n#{sales_str}"
      puts "NODE:\n#{node_str}"
      puts "MATCH? #{sales_str == node_str}"
      puts "-"*80
    end
  end
end
