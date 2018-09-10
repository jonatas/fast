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
```

The idea of this inspecton is build a proof of concept to show the similarity
of matcher classes because they only define a `match?` method.

```ruby
patterns = Fast.search_file('class','lib/fast.rb').map{|n|Fast.expression_from(n)}
```

A simple comparison between the patterns size versus `.uniq.size` can proof if
the idea will work.

```ruby
patterns.size == patterns.uniq.size
```

It does not work for the matcher cases but we can go deeper and analyze all
files required by bundler.

```ruby
similarities = {}
Gem.find_files('*.rb').each do |file|
  Fast.search_file('',file).map do |n|
    key = Fast.expression_from(n)
    similarities[key] ||= Set.new
    similarities[key] << file
  end 
end
similarities.delete_if {|k,v|v.size < 2}
```
The similarities found are the following:

```ruby
{"(class (const nil _) (const nil _) nil)"=>
  #<Set: {"/Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/gems/2.5.0/gems/parallel-1.12.1/lib/parallel.rb",
   "/Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/gems/2.5.0/gems/method_source-0.9.0/lib/method_source.rb",
   "/Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/2.5.0/rdoc.rb",
   "/Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/2.5.0/irb.rb",
   "/Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/2.5.0/tsort.rb"}>,
 "(class (const nil _) nil nil)"=>#<Set: {"/Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/2.5.0/ripper.rb", "/Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/2.5.0/cgi.rb"}>}
```

And now we can test the expression using the command line tool through the files
and observe the similarity:

⋊> ~ fast "(class (const nil _) (const nil _) nil)" /Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/gems/2.5.0/gems/parallel-1.12.1/lib/parallel.rb /Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/gems/2.5.0/gems/method_source-0.9.0/lib/method_source.rb /Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/2.5.0/rdoc.rb /Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/2.5.0/irb.rb /Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/2.5.0/tsort.rb
```ruby
# /Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/gems/2.5.0/gems/parallel-1.12.1/lib/parallel.rb:8
class DeadWorker < StandardError
end
# /Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/gems/2.5.0/gems/parallel-1.12.1/lib/parallel.rb:11
class Break < StandardError
end
# /Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/gems/2.5.0/gems/parallel-1.12.1/lib/parallel.rb:14
class Kill < StandardError
end
# /Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/gems/2.5.0/gems/method_source-0.9.0/lib/method_source.rb:16
class SourceNotFoundError < StandardError; end
# /Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/2.5.0/rdoc.rb:63
class Error < RuntimeError; end
# /Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/2.5.0/irb.rb:338
class Abort < Exception;end
# /Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/2.5.0/tsort.rb:125
class Cyclic < StandardError
end
```

It works and now we can create a method to do what the command line tool did, 
grouping the patterns and inspecting the occurrences.

```ruby
def similarities.show pattern
  files = self[pattern]
  files.each do |file|
    nodes = Fast.search_file(pattern, file)
    nodes.each do |result|
      Fast.report(result, file: file)
    end
  end
end
```
 
