require 'fast'
require 'fast/sql'

ast = Fast.parse_sql_file("cte_example.sql")

def walk(node, results = [])
  results << node if node.respond_to?(:type) && node.type == :select_stmt
  if node.respond_to?(:children)
    node.children.each do |child|
      if child.is_a?(Array)
        child.each { |c| walk(c, results) }
      else
        walk(child, results)
      end
    end
  end
  results
end

selects = walk(ast)
puts "Found #{selects.size} select_stmt nodes!"
selects.each_with_index do |s, i|
  puts "Select #{i+1}: length #{s.to_s.length}"
end

sales_2023 = selects[1] # The CTE query
puts "Sales 2023 object_id: #{sales_2023.object_id}"

selects.each_with_index do |node, i|
  puts "Comparing with Select #{i+1}:"
  puts "  object_id match? #{node.object_id == sales_2023.object_id}"
  puts "  to_s match? #{node.to_s.gsub(/\s+/, ' ') == sales_2023.to_s.gsub(/\s+/, ' ')}"
  
  if node.to_s.gsub(/\s+/, ' ') == sales_2023.to_s.gsub(/\s+/, ' ') && node.object_id != sales_2023.object_id
    puts "  >>> FOUND THE DUPLICATE! <<<"
  end
end
