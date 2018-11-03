# Fast

[![Build Status](https://travis-ci.org/jonatas/fast.svg?branch=master)](https://travis-ci.org/jonatas/fast)

Fast is a "Find AST" tool to help you search in the code abstract syntax tree.

Ruby allow us to do the same thing in a few ways then it's hard to check
how the code is written.

Check the official documentation: https://jonatas.github.io/fast.

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
- `%1` to bind the first extra argument
- `""` surround the value with double quotes to match literal strings

The syntax is inspired on [RuboCop Node Pattern](https://github.com/bbatsov/rubocop/blob/master/lib/rubocop/node_pattern.rb).

## Installation

    $ gem install ffast

## How it works

The idea is search in abstract tree using a simple expression build with an array:

A simple integer in ruby:

```ruby
1
```

Is represented by:

```ruby
s(:int, 1)
```

Basically `s` represents `Parser::AST::Node` and the node has a `#type` and `#children`.

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
## Bind arguments to expressions

Sometimes we need to define useful functions and bind arguments that will be
based on dynamic decisions or other external input.
For such cases you can bind the arguments with `%` and the index start from `1`.

Example:

```ruby
Fast.match?(code['a = 1'], '(lvasgn %1 (int _))', :a) # true
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
Fast.replace ast,
  '(def $_ ... (send (send nil $_) \1))',
  -> (node, captures) {
    attribute, object = captures
    replace(
      node.location.expression,
      "delegate :#{attribute}, to: :#{object}"
    )
  }
```

### Replacing file

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

## Other useful functions

To manipulate ruby files, some times you'll need some extra tasks.

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

## `fast` in the command line

It will also inject a executable named `fast` and you can use it to search and
find code using the concept:

```
$ fast '(def match?)' lib/fast.rb
```

- Use `-d` or `--debug` for enable debug mode.
- Use `--ast` to output the AST instead of the original code
- Use `--pry` to jump debugging the first result with pry
- Use `-c` to search from code example
- Use `-s` to search similar code

```
$ fast '(block (send nil it))' spec --pry
```
And inside pry session,  you can use `result` as the first result or `results`
to use all occurrences found.

```ruby
results.map{|e|e.children[0].children[2]}
# => [s(:str, "parses ... as Find"),
# s(:str, "parses $ as Capture"),
# s(:str, "parses quoted values as strings"),
# s(:str, "parses {} as Any"),
# s(:str, "parses [] as All"), ...]
```

Getting all `it` blocks without description:

    $ fast '(block (send nil it (nil)) (args ) (!str)) ) )' spec

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

You can define experiments and build experimental research to improve some code in
an automated way.

Let's create an experiment to try to remove `before` or `after` blocks
and run specs. If the spec pass without need the hook, the hook is useless.

```ruby
Fast.experiment("RSpec/RemoveUselessBeforeAfterHook") do
  lookup 'spec'
  search "(block (send nil {before after}))"
  edit {|node| remove(node.loc.expression) }
  policy {|new_file| system("bin/spring rspec --fail-fast #{new_file}") }
end
```

- In the `lookup` you can pass files or folders.
- The `search` contains the expression you want to match
- With `edit` block you can apply the code change
- And the `policy` is executed to check if the current change is valuable

If the file contains multiple `before` or `after` blocks, each removal will
occur independently and the successfull removals will be combined as a
secondary change. The process repeates until find all possible combinations.

See more examples in [experiments](experiments) folder.

To run multiple experiments, use `fast-experiment` runner:

```
fast-experiment <experiment-names> <files-or-folders>
```

You can limit experiments or file escope:

```
fast-experiment RSpec/RemoveUselessBeforeAfterHook spec/models/**/*_spec.rb
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

On the console we have a few functions like `s` and `code` to make it easy ;)

$ bin/console

```ruby
code("a = 1") # => s(:lvasgn, s(:int, 1))
```

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jonatas/fast. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).


See more on the [official documentation](https://jonatas.github.io/fast).
