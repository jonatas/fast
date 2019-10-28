
rewriter = Fast::Rewriter.new
rewriter.ast = Fast.ast("a = 1")
rewriter.search ='(lvasgn _ ...)'
rewriter.replacement =  -> (node) { replace(node.location.name, 'variable_renamed') }
puts rewriter.rewrite!
