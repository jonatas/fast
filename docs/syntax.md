# Syntax

The syntax is inspired on [RuboCop Node Pattern](https://github.com/bbatsov/rubocop/blob/master/lib/rubocop/node_pattern.rb).

You can find a great tutorial about RuboCop node pattern in the
[official documentation](https://rubocop.readthedocs.io/en/latest/node_pattern/).

The basic elemements are:

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

Let's consider the following `example.rb` code example:

```ruby
class Example
  ANSWER = 42
  def magic
    rand(ANSWER)
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

    $ fast def example.rb                                                                                                                                               20:34:21

```ruby
# example.rb:3
  def magic
    rand(ANSWER)
  end
```

or check the `casgn` that will show constant assignments:

    $ fast casgn example.rb                                                                                                                                             20:40:21

```ruby
# example.rb:2
ANSWER = 42
```

## `()` to represent a **node** search

To specify details about a node, the `(` means navigate deeply into a node and
go deep into the expression.

```
fast '(casgn' example.rb
```

```ruby
# example.rb:2
ANSWER = 42
```

Fast matcher never checks the end of the expression and close parens are not
necessary. We keep them for the sake of specify more node details but the
expression works with incomplete parens.

```
fast '(casgn)' example.rb
```

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

    $ fast '((casgn ' example.rb --ast                                                                                                                                  20:54:12

```ruby
# example.rb:2
(casgn nil :ANSWER
  (int 42))
```

## `_` is **something** not nil

Let's enhance our current expression and specify that we're looking for constant
assignments of integers ignoring values and constant names replacing with `_`.

    $ fast '(casgn nil _ (int _))' example.rb                                                    21:10:26

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

   $ fast '^int' example.rb                                                                                                                                           21:23:57

```ruby
# example.rb:2
ANSWER = 42
# example.rb:7
value * 2
```

And using it multiple times will make the node match from levels up:

    $ fast '^^int' example.rb                                                                                                                                          21:24:10

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

## join conditions with `[]`

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

    $ fast '(def _ ...)' example.rb                                                                                                                                    22:22:37

```ruby
# example.rb:6
def duplicate(value)
    value * 2
  end
```

If we use `(def _ _)` instead it will match both methods because `(args)` 
does not have children but is not nil.

## `$` is for **capture** current expression
## `nil` matches exactly **nil**
## `{}` is for **any** matches like **union** conditions with **or** operator
## `?` is for **maybe**
## `\1` to use the first **previous captured** element
## `""` surround the value with double quotes to match literal strings

