# Fast

Fast is a "Find AST" tool to help you search in the code abstract syntax tree.

Ruby allow us to do the same thing in a few ways then it's hard to check
how the code is written.

Using the AST will be easier than try to cover the multiple ways we can write
the same code.

You can define a string like `%||` or `''` or `""` but they will have the same
AST representation.

## AST representation

Each detail of the ruby syntax have a equivalent identifier and some
content. The content can be another expression or a final value.

Fast uses parser gem behind the scenes to parse the code into nodes.

First get familiar with parser gem and understand how ruby code is represented.

When you install parser gem, you will have access to `ruby-parse` and you can
use it with `-e` to parse an expression directly from the command line.

Example:

```
ruby-parse -e 1
```

It will print the following output:

```
(int 1)
```

And trying a number with decimals:

```
ruby-parse -e 1.1
(float 1)
```

Building a regex that will match decimals and integer looks like something easy
and with fast you use a node pattern that reminds the syntax of regular
expressions.

## Syntax for find in AST

The current version cover the following elements:

- `()` to represent a **node** search
- `{}` is for **any** matches like **union** conditions with **or** operator
- `[]` is for **all** matches like **intersect** conditions with **and** operator
- `$` is for **capture** current expression
- `_` is **something** not nil
- `nil` matches exactly **nil**
- `...` is a **node** with children
- `^` is to get the **parent node** of an expression
- `?` is for **maybe**
- `\1` to use the first **previous captured** element
- `""` surround the value with double quotes to match literal strings

Jump to [Syntax](syntax.md).

## Fast.match?

`match?` is the most granular function that tries to compare a node with an
expression. It returns true or false and some node captures case it find
something.

Let's start with a simple integer in Ruby:

```ruby
1
```

The AST can be represented with the following expression:

```
(int 1)
```

The ast representation holds node `type` and `children`.

Let's build a method `s` to represent `Parser::AST::Node` with a `#type` and `#children`.

```ruby
def s(type, *children)
  Parser::AST::Node.new(type, children)
end
```

A local variable assignment:

```ruby
value = 42
```

Can be represented with:

```ruby
ast = s(:lvasgn, :value, s(:int, 42))
```

Now, lets find local variable named `value` with an value `42`:

```ruby
Fast.match?(ast, '(lvasgn value (int 42))') # true
```

Lets abstract a bit and allow some integer value using `_` as a shortcut:

```ruby
Fast.match?(ast, '(lvasgn value (int _))') # true
```

Lets abstract more and allow float or integer:

```ruby
Fast.match?(ast, '(lvasgn value ({float int} _))') # true
```

Or combine multiple assertions using `[]` to join conditions:

```ruby
Fast.match?(ast, '(lvasgn value ([!str !hash !array] _))') # true
```

Matches all local variables not string **and** not hash **and** not array.

We can match "a node with children" using `...`:

```ruby
Fast.match?(ast, '(lvasgn value ...)') # true
```

You can use `$` to capture a node:

```ruby
Fast.match?(ast, '(lvasgn value $...)') # => [s(:int, 42)]
```

Or match whatever local variable assignment combining both `_` and `...`:

```ruby
Fast.match?(ast, '(lvasgn _ ...)') # true
```

You can also use captures in any levels you want:

```ruby
Fast.match?(ast, '(lvasgn $_ $...)') # [:value, s(:int, 42)]
```

Keep in mind that `_` means something not nil and `...` means a node with
children.

Then, if do you get a method declared:

```ruby
def my_method
  call_other_method
end
```
It will be represented with the following structure:

```ruby
ast =
  s(:def, :my_method,
    s(:args),
    s(:send, nil, :call_other_method))
```

Keep an eye on the node `(args)`.

Then you know you can't use `...` but you can match with `(_)` to match with
such case.

Let's test a few other examples. You can go deeply with the arrays. Let's suppose we have a hardcore call to
`a.b.c.d` and the following AST represents it:

```ruby
ast =
  s(:send,
    s(:send,
      s(:send,
        s(:send, nil, :a),
        :b),
      :c),
    :d)
```

You can search using sub-arrays with **pure values**, or **shortcuts** or
**procs**:

```ruby
Fast.match?(ast, [:send, [:send, '...'], :d]) # => true
Fast.match?(ast, [:send, [:send, '...'], :c]) # => false
Fast.match?(ast, [:send, [:send, [:send, '...'], :c], :d]) # => true
```

Shortcuts like `...` and `_` are just literals for procs. Then you can use
procs directly too:

```ruby
Fast.match?(ast, [:send, [ -> (node) { node.type == :send }, [:send, '...'], :c], :d]) # => true
```

And also work with expressions:

```ruby
Fast.match?(
  ast,
  '(send (send (send (send nil $_) $_) $_) $_)'
) # => [:a, :b, :c, :d]
```

If something does not work you can debug with a block:

```ruby
Fast.debug { Fast.match?(s(:int, 1), [:int, 1]) }
```

It will output each comparison to stdout:

```
int == (int 1) # => true
1 == 1 # => true
```

## Use previous captures in search

Imagine you're looking for a method that is just delegating something to
another method, like:

```ruby
def name
  person.name
end
```

This can be represented as the following AST:

```
(def :name
  (args)
  (send
    (send nil :person) :name))
```

Then, let's build a search for methods that calls an attribute with the same
name:

```ruby
Fast.match?(ast,'(def $_ ... (send (send nil _) \1))') # => [:name]
```

## Fast.search

Search allows you to go deeply in the AST, collecting nodes that matches with
the expression. It also returns captures if they exist.

```ruby
Fast.search(code('a = 1'), '(int _)') # => s(:int, 1)
```

If you use captures, it returns the node and the captures respectively:

```ruby
Fast.search(code('a = 1'), '(int $_)') # => [s(:int, 1), 1]
```

## Fast.capture

To pick just the captures and ignore the nodes, use `Fast.capture`:

```ruby
Fast.capture(code('a = 1'), '(int $_)') # => 1
```
## Fast.replace

And if I want to refactor a code and use `delegate <attribute>, to: <object>`, try with replace:

```ruby
Fast.replace ast, '(def $_ ... (send (send nil $_) \1))' do |node, captures|
    attribute, object = captures
    replace(
      node.location.expression,
      "delegate :#{attribute}, to: :#{object}"
    )
  end
```

## Fast.replace_file

Now let's imagine we have real files like `sample.rb` with the following code:

```ruby
def good_bye
  message = ["good", "bye"]
  puts message.join(' ')
end
```

And we decide to remove the `message` variable and put it inline with the `puts`.

Basically, we need to find the local variable assignment, store the value in
memory. Remove the assignment expression and use the value where the variable
is being called.

```ruby
assignment = nil
Fast.replace_file('sample.rb', '({ lvasgn lvar } message )',
  -> (node, _) {
    if node.type == :lvasgn
      assignment = node.children.last
      remove(node.location.expression)
    elsif node.type == :lvar
      replace(node.location.expression, assignment.location.expression.source)
    end
  }
)
```

## Fast.ast_from_File(file)

This method parses the code and load into a AST representation.

```ruby
Fast.ast_from_file('sample.rb')
```

## Fast.search_file

You can use `search_file` and pass the path for search for expressions inside
files.

```ruby
Fast.search_file(expression, 'file.rb')
```

It's simple combination of `Fast.ast_from_file` with `Fast.search`.

## Fast.ruby_files_from(arguments)

You'll be probably looking for multiple ruby files, then this method fetches
all internal `.rb` files 

```ruby
Fast.ruby_files_from(['lib']) # => ["lib/fast.rb"]
```

