# Syntax

The syntax is inspired on [RuboCop Node Pattern](https://github.com/bbatsov/rubocop/blob/master/lib/rubocop/node_pattern.rb).

You can find a great tutorial about RuboCop node pattern in the
[official documentation](https://rubocop.readthedocs.io/en/latest/node_pattern/).

## Code example

Let's consider the following `example.rb` code example:

```ruby
class Example
  ANSWER = 42
  def magic
    rand(ANSWER)
  end
  def duplicate(value)
    value * 2
  end
end
```

Looking the AST representation we have:

    $ ruby-parse example.rb

```
(class
  (const nil :Example) nil
  (begin
    (casgn nil :ANSWER
      (int 42))
    (def :magic
      (args)
      (send nil :rand
        (const nil :ANSWER)))
    (def :duplicate
      (args
        (arg :value))
      (send
        (lvar :value) :*
        (int 2)))))
```  

Now, let's explore all details of the current AST, combining with the syntax
operators.

Fast works with a single word that will be the node type.

A simple search of `def` nodes can be done and will also print the code.

    $ fast def example.rb

```ruby
# example.rb:3
  def magic
    rand(ANSWER)
  end
```

or check the `casgn` that will show constant assignments:

    $ fast casgn example.rb

```ruby
# example.rb:2
ANSWER = 42
```

## `()` to represent a **node** search

To specify details about a node, the `(` means navigate deeply into a node and
go deep into the expression.

    $ fast '(casgn' example.rb

```ruby
# example.rb:2
ANSWER = 42
```

Fast matcher never checks the end of the expression and close parens are not
necessary. We keep them for the sake of specify more node details but the
expression works with incomplete parens.

    $ fast '(casgn)' example.rb

```ruby
# example.rb:2
ANSWER = 42
```

Closing extra params also don't have a side effect.

    $ fast '(casgn))' example.rb

```ruby
# example.rb:2
ANSWER = 42
```

It also automatically flat parens case you put more levels in the beginning.

    $ fast '((casgn))' example.rb

```ruby
# example.rb:2
ANSWER = 42
```

For checking AST details while doing some search, you can use `--ast` in the
command line for printing the AST instead of the code:

    $ fast '((casgn ' example.rb --ast

```ruby
# example.rb:2
(casgn nil :ANSWER
  (int 42))
```

## `_` is **something** not nil

Let's enhance our current expression and specify that we're looking for constant
assignments of integers ignoring values and constant names replacing with `_`.

    $ fast '(casgn nil _ (int _))' example.rb

```ruby
# example.rb:2
ANSWER = 42
```

Keep in mind that `_` means not nil and  `(casgn _ _ (int  _))` would not
match.

Let's search for integer nodes:

    $ fast int example.rb
```ruby
# example.rb:2
42
# example.rb:7
2
```

The current search show the nodes but they are not so useful without understand
the expression in their context. We need to check their `parent`.

## `^` is to get the **parent node** of an expression

By default, Parser::AST::Node  does not have access to parent and for accessing
it you can say `^` for reaching the parent.

    $ fast '^int' example.rb

```ruby
# example.rb:2
ANSWER = 42
# example.rb:7
value * 2
```

And using it multiple times will make the node match from levels up:

    $ fast '^^int' example.rb

```ruby
# example.rb:2
ANSWER = 42
  def magic
    rand(ANSWER)
  end
  def duplicate(value)
    value * 2
  end
```

## `[]` join conditions

Let's hunt for integer nodes that the parent is also a method:

    $ fast '[ ^^int def ]' example.rb

The match will filter only nodes that matches all internal expressions.

```ruby
# example.rb:6
def duplicate(value)
    value * 2
  end
```

The expression is matching nodes that have a integer granchild and also with
type `def`.

## `...` is a **node** with children

Looking the method representation we have:

    $ fast def example.rb --ast

```ruby
# example.rb:3
(def :magic
  (args)
  (send nil :rand
    (const nil :ANSWER)))
# example.rb:6
(def :duplicate
  (args
    (arg :value))
  (send
    (lvar :value) :*
    (int 2)))
```

And if we want to delimit only methods with arguments:

    $ fast '(def _ ...)' example.rb

```ruby
# example.rb:6
def duplicate(value)
    value * 2
  end
```

If we use `(def _ _)` instead it will match both methods because `(args)` 
does not have children but is not nil.

## `$` is for **capture** current expression

Now, let's say we want to extract some method name from current classes.

In such case we don't want to have the node definition but only return the node
name.

```ruby
# example.rb:2
def magic
    rand(ANSWER)
  end
# example.rb:
magic
# example.rb:9
def duplicate(value)
    value * 2
  end
# example.rb:
duplicate
```

One extra method name was printed because of `$` is capturing the element.

## `nil` matches exactly **nil**

Nil is used in the code as a node type but parser gem also represents empty
spaces in expressions with nil.

Example, a method call from Kernel is a `send` from `nil` calling the method
while I can also send a method call from a class.

```
$ ruby-parse -e 'method'
(send nil :method)
```

And a method from a object will have the nested target not nil.

```
$ ruby-parse -e 'object.method'
(send
  (send nil :object) :method)
```

Let's build a serch for any calls from `nil`:

    $ fast '(_ nil _)' example.rb

```ruby
# example.rb:3
Example
# example.rb:4
ANSWER = 42
# example.rb:6
rand(ANSWER)
```

Double check the expressions that have matched printing the AST:

    $ fast '(_ nil _)' example.rb --ast

```ruby
# example.rb:3
(const nil :Example)
# example.rb:4
(casgn nil :ANSWER
  (int 42))
# example.rb:6
(send nil :rand
  (const nil :ANSWER))
```

## `{}` is for **any** matches like **union** conditions with **or** operator

Let's say we to add check all occurrencies of the constant `ANSWER`.

We'll need to get both `casgn` and `const` node types. For such cases we can
surround the expressions with `{}` and it will return if the node matches with
any of the internal expressions.

    $ fast '({casgn const} nil ANSWER)' example.rb

```
# example.rb:4
ANSWER = 42
# example.rb:6
ANSWER
```

## `#` for custom methods

Custom methods can let you into ruby doman for more complicated rules. Let's say
we're looking for duplicated methods in the same class. We need to collect
method names and guarantee they are unique.

```ruby
def duplicated(method_name)
  @methods ||= []
  already_exists = @methods.include?(method_name)
  @methods << method_name
  already_exists
end

puts Fast.search_file( '(def #duplicated)', 'example.rb')
```
The same principle can be used in the node level or for debugging purposes.

```ruby
require 'pry'
def debug(node)
  binding.pry
end

puts Fast.search_file('#debug', 'example.rb')
```
If you want to get only `def` nodes you can also intersect expressions with `[]`:
```ruby
puts Fast.search_file('[ def #debug ]', 'example.rb')
```
Or if you want to debug a very specific expression you can use `()` to specify
more details of the node
```ruby
puts Fast.search_file('[ (def a) #debug ]', 'example.rb')
```

## `.` for instance methods

You can also call instance methods using `.<method-name>`.

Example `nil` is the same of calling `nil?` and you can also use `(int .odd?)`
to pick only odd integers. The `int` fragment can also be `int_type?`.

## `\1` for first previous capture

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
Fast.match?('(def $_ ... (send (send nil _) \1))', ast) # => [:name]
```

With the method name being captured with `$_` it can be later referenced in the
expression with `\1`. If the search contains multiple captures, the `\2`,`\3`
can be used as the sequence of captures.
