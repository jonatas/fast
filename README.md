# Fast

[![Build Status](https://travis-ci.org/jonatas/fast.svg?branch=master)](https://travis-ci.org/jonatas/fast)

Fast, short for "Find AST", is a tool to search, prune, and edit Ruby ASTs.

Ruby is a flexible language that allows us to write code in multiple different ways
to achieve the same end result, and because of this it's hard to verify how
the code was written without an AST.

Check out the official documentation: https://jonatas.github.io/fast.

## Token Syntax for `find` in AST

The current version of Fast covers the following token elements:

- `()` - represents a **node** search
- `{}` - looks for **any** element to match, like a **Set** inclusion or `any?` in Ruby
- `[]` - looks for **all** elements to match, like `all?` in Ruby.
- `$` - will **capture** the contents of the current expression like a `Regex` group
- `_` - represents any non-nil value, or **something** being present
- `nil` -  matches exactly **nil**
- `...` - matches a **node** with children
- `^` - references the **parent node** of an expression
- `?` - represents an element which **maybe** present
- `\1` - represents a substitution for any of the **previously captured** elements
- `%1` - to bind the first extra argument in an expression
- `""` - will match a literal string with double quotes

The syntax is inspired by the [RuboCop Node Pattern](https://github.com/bbatsov/rubocop/blob/master/lib/rubocop/node_pattern.rb).

## Installation

    $ gem install ffast

## How it works

### S-Expressions

Fast works by searching the abstract syntax tree using a series of expressions
to represent code called `s-expressions`.

> `s-expressions`, or symbolic expressions, are a way to represent nested data.
> They originate from the LISP programming language, and are frequetly used in
> other languages to represent ASTs.

### Integer Literals

For example, let's take an `Integer` in Ruby:

```ruby
1
```

It's corresponding s-expression would be:

```ruby
s(:int, 1)
```

`s` in `Fast` and `Parser` are a shorthand for creating an `Parser::AST::Node`.
Each of these nodes has a `#type` and `#children` contained in it:

```ruby
def s(type, *children)
  Parser::AST::Node.new(type, children)
end
```

### Variable Assignments

Now let's take a look at a local variable assignment:

```ruby
value = 42
```

It's corresponding s-expression would be:

```ruby
ast = s(:lvasgn, :value, s(:int, 42))
```

If we wanted to find this particular assignment somewhere in our AST, we can use
Fast to look for a local variable named `value` with a value `42`:

```ruby
Fast.match?(ast, '(lvasgn value (int 42))')
# => true
```

### Wildcard Token

If we wanted to find a variable named `value` that was assigned any integer value
we could replace `42` in our query with an underscore ( `_` ) as a shortcut:

```ruby
Fast.match?(ast, '(lvasgn value (int _))')
# => true
```

### Set Inclusion Token

If we weren't sure the type of the value we're assigning, we can use our set
inclusion token (`{}`) from earlier to tell Fast that we expect either a `Float`
or an `Integer`:

```ruby
Fast.match?(ast, '(lvasgn value ({float int} _))')
# => true
```

### All Matching Token

Say we wanted to say what we expect the value's type to _not_ be, we can use the
all matching token (`[]`) to express multiple conditions that need to be true.
In this case we don't want the value to be a `String`, `Hash`, or an `Array` by
prefixing all of the types with `!`:

```ruby
Fast.match?(ast, '(lvasgn value ([!str !hash !array] _))') # true
```

### Node Child Token

We can match any node with children by using the child token ( `...` ):

```ruby
Fast.match?(ast, '(lvasgn value ...)')
# => true
```

We could even match any local variable assignment combining both `_` and `...`:

```ruby
Fast.match?(ast, '(lvasgn _ ...)')
# => true
```

### Capturing the Value of an Expression

You can use `$` to capture the contents of an expression for later use:

```ruby
Fast.match?(ast, '(lvasgn value $...)')
# => [s(:int, 42)]
```

Captures can be used in any position as many times as you want to capture whatever
information you might need:

```ruby
Fast.match?(ast, '(lvasgn $_ $...)')
# => [:value, s(:int, 42)]
```

> Keep in mind that `_` means something not nil and `...` means a node with
> children.

### Methods

Let's take a look at a method declaration:

```ruby
def my_method
  call_other_method
end
```

It's corresponding s-expression would be:

```ruby
ast =
  s(:def, :my_method,
    s(:args),
    s(:send, nil, :call_other_method))
```

Pay close attention to the node `(args)`. We can't use `...` to match it, as it
has no children (or arguments in this case), but we _can_ match it with a wildcard
`_` as it's not `nil`.

### Call Chains

Let's take a look at a few other examples. Sometimes you have a chain of calls on
a single `Object`, like `a.b.c.d`. Its corresponding s-expression would be:

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

### Alternate Syntax

You can also search using nested arrays with **pure values**, or **shortcuts** or
**procs**:

```ruby
Fast.match?(ast, [:send, [:send, '...'], :d])
# => true

Fast.match?(ast, [:send, [:send, '...'], :c])
# => false

Fast.match?(ast, [:send, [:send, [:send, '...'], :c], :d])
# => true
```

Shortcut tokens like child nodes `...` and wildcards `_` are just placeholders
for procs. If you want, you can even use procs directly like so:

```ruby
Fast.match?(ast, [
  :send, [
    -> (node) { node.type == :send },
    [:send, '...'],
    :c
  ],
  :d
])
# => true
```

This also works with expressions:

```ruby
Fast.match?(
  ast,
  '(send (send (send (send nil $_) $_) $_) $_)'
)
# => [:a, :b, :c, :d]
```

### Debugging

If you find that a particular expression isn't working, you can use `debug` to
take a look at what Fast is doing:

```ruby
Fast.debug { Fast.match?(s(:int, 1), [:int, 1]) }
```

Each comparison made while searching will be logged to your console (STDOUT) as
Fast goes through the AST:

```
int == (int 1) # => true
1 == 1 # => true
```

## Bind arguments to expressions

We can also dynamically interpolate arguments into our queries using the
interpolation token `%`. This works much like `sprintf` using indexes starting
from `1`:

```ruby
Fast.match?(code('a = 1'), '(lvasgn %1 (int _))', :a)
# => true
```

## Using previous captures in search

Imagine you're looking for a method that is just delegating something to
another method, like this `name` method:

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

We can create a query that searches for such a method:

```ruby
Fast.match?(ast,'(def $_ ... (send (send nil _) \1))')
# => [:name]
```

## Fast.search

Search allows you to go search the entire AST, collecting nodes that matcha given
expression. Any matching node is then returned:

```ruby
Fast.search(code('a = 1'), '(int _)')
# => s(:int, 1)
```

If you use captures along with a search, both the matching nodes and the
captures will be returned:

```ruby
Fast.search(code('a = 1'), '(int $_)')
# => [s(:int, 1), 1]
```

## Fast.capture

To only pick captures and ignore the nodes, use `Fast.capture`:

```ruby
Fast.capture(code('a = 1'), '(int $_)')
# => 1
```
## Fast.replace

<!--
  Not sure how this section works, could you explain it in more detail?

  It looks to capture the name of a method, and then not sure from there. Can
  you provide an example AST to use there?

  Delegate might be too dense of an example to use.
-->

If we want to replace code, we can use a delegate expression:

```ruby
query = '(def $_ ... (send (send nil $_) \1))'

Fast.replace ast, query, -> (node, captures) {
  attribute, object = captures

  replace(
    node.location.expression,
    "delegate :#{attribute}, to: :#{object}"
  )
}
```

### Replacing file

Now let's imagine we have a file like `sample.rb` with the following code:

```ruby
def good_bye
  message = ["good", "bye"]
  puts message.join(' ')
end
```

...and we decide to inline the contents of the `message` variable right after
`puts`.


To do this we would need to:

* Remove the local variable assignment
* Store the now-removed variable's value
* Substitute the value where the variable was used before

```ruby
assignment = nil
query = '({ lvasgn lvar } message )'

Fast.replace_file('sample.rb', query, -> (node, _) {
  # Find a variable assignment
  if node.type == :lvasgn
    assignment = node.children.last

    # Remove the node responsible for the assignment
    remove(node.location.expression)
  # Look for the variable being used
  elsif node.type == :lvar
    # Replace the variable with the contents of the variable
    replace(
      node.location.expression,
      assignment.location.expression.source
    )
  end
})
```

## Other useful functions

To manipulate ruby files, sometimes you'll need some extra tasks.

## Fast.ast_from_File(file)

This method parses code from a file and loads it into an AST representation.

```ruby
Fast.ast_from_file('sample.rb')
```

## Fast.search_file

You can use `search_file` to for search for expressions inside files.

```ruby
Fast.search_file(expression, 'file.rb')
```

It's a combination of `Fast.ast_from_file` with `Fast.search`.

## Fast.capture_file

You can use `Fast.capture_file` to only return captures:

```ruby
 Fast.capture_file('(class (const nil $_))', 'lib/fast.rb')
 # => [:Rewriter, :ExpressionParser, :Find, :FindString, ...]
```

## Fast.ruby_files_from(arguments)

`Fast.ruby_files_from(arguments)` can get all Ruby files in a location:

```ruby
Fast.ruby_files_from('lib')
# => ["lib/fast.rb"]
```

## `fast` in the command line

Fast also comes with a command line utility called `fast`. You can use it to
search and find code much like the library version:

```
$ fast '(def match?)' lib/fast.rb
```

The CLI tool takes the following flags

- Use `-d` or `--debug` for enable debug mode.
- Use `--ast` to output the AST instead of the original code
- Use `--pry` to jump debugging the first result with pry
- Use `-c` to search from code example
- Use `-s` to search similar code

### Fast with Pry

You can use `--pry` to stop on a particular source node, and run Pry at that
location:

```
$ fast '(block (send nil it))' spec --pry
```

Inside the pry session you can access `result` for the first result that was
located, or `results` to get all of the occurrences found.

Let's take a look at `results`:

```ruby
results.map { |e| e.children[0].children[2] }
# => [s(:str, "parses ... as Find"),
# s(:str, "parses $ as Capture"),
# s(:str, "parses quoted values as strings"),
# s(:str, "parses {} as Any"),
# s(:str, "parses [] as All"), ...]
```

### Fast with RSpec

Let's say we wanted to get all the `it` blocks in our `RSpec` code that
currently do not have descriptions:

```
$ fast '(block (send nil it (nil)) (args) (!str)) ) )' spec
```

This will return the following:

```ruby
# spec/fast_spec.rb:166
it { expect(described_class).to be_match(s(:int, 1), '(...)') }
# spec/fast_spec.rb:167
it { expect(described_class).to be_match(s(:int, 1), '(_ _)') }
# spec/fast_spec.rb:168
it { expect(described_class).to be_match(code['"string"'], '(str "string")') }
# ... more results
```

## Experiments

Experiments can be used to run experiments against your code in an automated
fashion. These experiments can be used to test the effectiveness of things
like performance enhancements, or if a replacement piece of code actually works
or not.

Let's create an experiment to try and remove all `before` and `after` blocks
from our specs.

If the spec still pass we can confidently say that the hook is useless.

```ruby
Fast.experiment("RSpec/RemoveUselessBeforeAfterHook") do
  # Lookup our spec files
  lookup 'spec'

  # Look for every block starting with before or after
  search "(block (send nil {before after}))"

  # Remove those blocks
  edit { |node| remove(node.loc.expression) }

  # Create a new file, and run RSpec against that new file
  policy { |new_file| system("bin/spring rspec --fail-fast #{new_file}") }
end
```

- `lookup` can be used to pass in files or folders.
- `search` contains the expression you want to match
- `edit` is used to apply code change
- `policy` is what we execute to verify the current change still passes

Each removal of a `before` and `after` block will occur in isolation to verify
each one of them independently of the others. Each successful removal will be
kept in a secondary change until we run out of blocks to remove.

You can see more examples in the [experiments](experiments) folder.

### Running Multiple Experiments

To run multiple experiments, use `fast-experiment` runner:

```
fast-experiment <experiment-names> <files-or-folders>
```

You can limit the scope of experiments:

```
fast-experiment RSpec/RemoveUselessBeforeAfterHook spec/models/**/*_spec.rb
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

On the console we have a few functions like `s` and `code` to make it easy ;)

```
$ bin/console
```

```ruby
code("a = 1") # => s(:lvasgn, s(:int, 1))
```

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jonatas/fast. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

See more on the [official documentation](https://jonatas.github.io/fast).
