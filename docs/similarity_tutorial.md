# Research for code similarity

This is a small tutorial to explore code similarity.

The major idea is register all expression styles and see if we can find some
similarity between the structures.

First we need to create a function that can analyze AST nodes and extract a
pattern from the expression.

The expression needs to generalize final node values and recursively build a
pattern that can be used as a search expression.

```ruby
def expression_from(node)
  case node
  when Parser::AST::Node
    if node.children.any?
      children_expression = node.children
        .map(&method(:expression_from))
        .join(' ')
      "(#{node.type} #{children_expression})"
    else
      "(#{node.type})"
    end
  when nil, 'nil'
    'nil'
  when Symbol, String, Integer
    '_'
  when Array, Hash
    '...'
  else
    node
  end
end
```

The pattern generated only flexibilize the search allowing us to group similar nodes.

Example:

```ruby
expression_from(code['1']) # =>'(int _)'
expression_from(code['nil']) # =>'(nil)'
expression_from(code['a = 1']) # =>'(lvasgn _ (int _))'
expression_from(code['def name; person.name end']) # =>'(def _ (args) (send (send nil _) _))'
```

The current method can translate all kind of expressions and the next step is
observe some specific node types and try to group the similarities
using the pattern generated.

```ruby
Fast.search_file('lib/fast.rb', 'class')
```
Capturing the constant name and filtering only for symbols is easy and we can
see that we have a few classes defined in the the same file.

```ruby
Fast.search_file('(class (const nil $_))','lib/fast.rb').grep(Symbol)
=> [:Rewriter,
 :ExpressionParser,
 :Find,
 :FindString,
 :FindWithCapture,
 :Capture,
 :Parent,
 :Any,
 :All,
 :Not,
 :Maybe,
 :Matcher,
 :Experiment,
 :ExperimentFile]

The idea of this inspecton is build a proof of concept to show the similarity
of matcher classes because they only define a `match?` method.

```ruby
Fast.search_file('class','lib/fast.rb').map{|n|Fast.expression_from(n)}
```




