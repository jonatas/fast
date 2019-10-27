# Fast

[![Build Status](https://travis-ci.org/jonatas/fast.svg?branch=master)](https://travis-ci.org/jonatas/fast)
[![Maintainability](https://api.codeclimate.com/v1/badges/b03d62ee266399e76e32/maintainability)](https://codeclimate.com/github/jonatas/fast/maintainability)
[![Test Coverage](https://api.codeclimate.com/v1/badges/b03d62ee266399e76e32/test_coverage)](https://codeclimate.com/github/jonatas/fast/test_coverage)

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
- `#<method-name>` - will call `<method-name>` with `node` as param allowing you
    to build custom rules.
- `.<method-name>` - will call `<method-name>` from the `node`

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

    1

It's corresponding s-expression would be:

    s(:int, 1)

`s` in `Fast` and `Parser` are a shorthand for creating an `Parser::AST::Node`.
Each of these nodes has a `#type` and `#children` contained in it:

    def s(type, *children)
      Parser::AST::Node.new(type, children)
    end

### Variable Assignments

Now let's take a look at a local variable assignment:

    value = 42

It's corresponding s-expression would be:

    ast = s(:lvasgn, :value, s(:int, 42))

If we wanted to find this particular assignment somewhere in our AST, we can use
Fast to look for a local variable named `value` with a value `42`:

    Fast.match? '(lvasgn value (int 42))', ast # => true

### Wildcard Token

If we wanted to find a variable named `value` that was assigned any integer value
we could replace `42` in our query with an underscore ( `_` ) as a shortcut:

    Fast.match? '(lvasgn value (int _))', ast # => true

### Set Inclusion Token

If we weren't sure the type of the value we're assigning, we can use our set
inclusion token (`{}`) from earlier to tell Fast that we expect either a `Float`
or an `Integer`:

    Fast.match? '(lvasgn value ({float int} _))', ast # => true

### All Matching Token

Say we wanted to say what we expect the value's type to _not_ be, we can use the
all matching token (`[]`) to express multiple conditions that need to be true.
In this case we don't want the value to be a `String`, `Hash`, or an `Array` by
prefixing all of the types with `!`:

    Fast.match? '(lvasgn value ([!str !hash !array] _))', ast # => true

### Node Child Token

We can match any node with children by using the child token ( `...` ):

    Fast.match? '(lvasgn value ...)', ast # => true

We could even match any local variable assignment combining both `_` and `...`:

    Fast.match? '(lvasgn _ ...)', ast # => true

### Capturing the Value of an Expression

You can use `$` to capture the contents of an expression for later use:

    Fast.match?(ast, '(lvasgn value $...)') # => [s(:int, 42)]

Captures can be used in any position as many times as you want to capture whatever
information you might need:

    Fast.match?(ast, '(lvasgn $_ $...)') # => [:value, s(:int, 42)]

> Keep in mind that `_` means something not nil and `...` means a node with
> children.

### Calling Custom Methods

You can also define custom methods to set more complicated rules. Let's say
we're looking for duplicated methods in the same class. We need to collect
method names and guarantee they are unique.

    def duplicated(method_name)
      @methods ||= []
      already_exists = @methods.include?(method_name)
      @methods << method_name
      already_exists
    end

    puts Fast.search_file('(def #duplicated)', 'example.rb')

The same principle can be used in the node level or for debugging purposes.

    require 'pry'
    def debug(node)
      binding.pry
    end

    puts Fast.search_file('#debug', 'example.rb')

If you want to get only `def` nodes you can also intersect expressions with `[]`:

    puts Fast.search_file('[ def #debug ]', 'example.rb')

### Methods

Let's take a look at a method declaration:

  def my_method
    call_other_method
  end

It's corresponding s-expression would be:

    ast =
      s(:def, :my_method,
        s(:args),
        s(:send, nil, :call_other_method))

Pay close attention to the node `(args)`. We can't use `...` to match it, as it
has no children (or arguments in this case), but we _can_ match it with a wildcard
`_` as it's not `nil`.

### Call Chains

Let's take a look at a few other examples. Sometimes you have a chain of calls on
a single `Object`, like `a.b.c.d`. Its corresponding s-expression would be:

    ast =
      s(:send,
        s(:send,
          s(:send,
            s(:send, nil, :a),
            :b),
          :c),
        :d)

### Alternate Syntax

You can also search using nested arrays with **pure values**, or **shortcuts** or
**procs**:

    Fast.match? ast, [:send, [:send, '...'], :d]  # => true
    Fast.match? ast, [:send, [:send, '...'], :c]  # => false

Shortcut tokens like child nodes `...` and wildcards `_` are just placeholders
for procs. If you want, you can even use procs directly like so:

    Fast.match?(ast, [
      :send, [
        -> (node) { node.type == :send },
        [:send, '...'],
        :c
      ],
      :d
    ]) # => true

This also works with expressions:

    Fast.match?(
      ast,
      '(send (send (send (send nil $_) $_) $_) $_)'
    ) # => [:a, :b, :c, :d]

### Debugging

If you find that a particular expression isn't working, you can use `debug` to
take a look at what Fast is doing:

    Fast.debug { Fast.match?(s(:int, 1), [:int, 1])  }

Each comparison made while searching will be logged to your console (STDOUT) as
Fast goes through the AST:

    int == (int 1) # => true
    1 == 1 # => true

## Bind arguments to expressions

We can also dynamically interpolate arguments into our queries using the
interpolation token `%`. This works much like `sprintf` using indexes starting
from `1`:

    Fast.match? :a, code('a = 1'), '(lvasgn %1 (int _))' # => true

## Using previous captures in search

Imagine you're looking for a method that is just delegating something to
another method, like this `name` method:

    def name
      person.name
    end

This can be represented as the following AST:

    (def :name
      (args)
      (send
        (send nil :person) :name))

We can create a query that searches for such a method:

    Fast.match?(ast,'(def $_ ... (send (send nil _) \1))') # => [:name]

## Fast.search

Search allows you to go search the entire AST, collecting nodes that matches given
expression. Any matching node is then returned:

    Fast.search(code('a = 1'), '(int _)') # => s(:int, 1)

If you use captures along with a search, both the matching nodes and the
captures will be returned:

    Fast.search(code('a = 1'), '(int $_)') # => [s(:int, 1), 1]

## Fast.capture

To only pick captures and ignore the nodes, use `Fast.capture`:

  Fast.capture(code('a = 1'), '(int $_)') # => 1

## Fast.replace

Let's consider the following example:

    def name
      person.name
    end

And, we want to replace code to use `delegate` in the expression:

    delegate :name, to: :person

We already target this example using `\1` on 
[Search and refer to previous capture](#using-previous-captures-in-search) and
now it's time to know about how to rewrite content.

The [Fast.replace](Fast#replace-class_method) yields a #{Fast::Rewriter} context.
The internal replace method accepts a range and every `node` have
a `location` with metadata about ranges of the node expression.

    ast = Fast.ast("def name; person.name end")
    # => s(:def, :name, s(:args), s(:send, s(:send, nil, :person), :name))

Generally, we  use the `location.expression`:

    ast.location.expression # => #<Parser::Source::Range (string) 0...25>

But location also brings some metadata about specific fragments:

    ast.location.instance_variables
    # => [:@keyword, :@operator, :@name, :@end, :@expression, :@node]

Range for the keyword that identifies the method definition:

    ast.location.keyword # => #<Parser::Source::Range (string) 0...3>

You can always pick the source of a source range:

    ast.location.keyword.source # => "def"

Or only the method name:

    ast.location.name # => #<Parser::Source::Range (string) 4...8>
    ast.location.name.source # => "name"

In the context of the rewriter, the objective is removing the method and inserting the new
delegate content. Then, the scope is `node.location.expression`:

    Fast.replace ast, '(def $_ ... (send (send nil $_) \1))' do |node, captures|
      attribute, object = captures

      replace(
        node.location.expression,
        "delegate :#{attribute}, to: :#{object}"
      )
    end


### Replacing file

Now let's imagine we have a file like `sample.rb` with the following code:

    def good_bye
      message = ["good", "bye"]
      puts message.join(' ')
    end

and we decide to inline the contents of the `message` variable right after

    def good_bye
      puts ["good", "bye"].join(' ')
    end


To refactor and reach the proposed example, follow a few steps:

1. Remove the local variable assignment
2. Store the now-removed variable's value
3. Substitute the value where the variable was used before

#### Entire example

    assignment = nil
    Fast.replace_file '({ lvasgn lvar } message )', 'sample.rb' do |node, _|
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
    end 

Keep in mind the current example returns a content output but do not rewrite the
file.

## Other utility functions

To manipulate ruby files, sometimes you'll need some extra tasks.

## Fast.ast_from_file(file)

This method parses code from a file and loads it into an AST representation.

    Fast.ast_from_file('sample.rb')

## Fast.search_file

You can use `search_file` to for search for expressions inside files.

    Fast.search_file(expression, 'file.rb')

It's a combination of `Fast.ast_from_file` with `Fast.search`.

## Fast.capture_file

You can use `Fast.capture_file` to only return captures:

    Fast.capture_file('(class (const nil $_))', 'lib/fast.rb')
    # => [:Rewriter, :ExpressionParser, :Find, :FindString, ...]

## Fast.ruby_files_from(arguments)

The `Fast.ruby_files_from(arguments)` can get all ruby files from file list or folders:

    Fast.ruby_files_from('lib') 
    # => ["lib/fast/experiment.rb", "lib/fast/cli.rb", "lib/fast/version.rb", "lib/fast.rb"]

## `fast` in the command line

Fast also comes with a command line utility called `fast`. You can use it to
search and find code much like the library version:

    fast '(def match?)' lib/fast.rb

The CLI tool takes the following flags

- Use `-d` or `--debug` for enable debug mode.
- Use `--ast` to output the AST instead of the original code
- Use `--pry` to jump debugging the first result with pry
- Use `-c` to search from code example
- Use `-s` to search similar code

### Define your `Fastfile`

Fastfile is loaded when you start a pattern with a `.`.

You can also define extra Fastfile in your home dir or setting a directory with
the `FAST_FILE_DIR`.

You can define a `Fastfile` in any project with your custom shortcuts.

```ruby
Fast.shortcut(:version, '(casgn nil VERSION (str _))', 'lib/fast/version.rb')
```

Let's say you'd like to show the version of your library. Your normal
command line will look like:

    $ fast '(casgn nil VERSION)' lib/*/version.rb

Or generalizing to search all constants in the version files:

    $ fast casgn lib/*/version.rb

It will output but the command is not very handy. In order to just say `fast .version`
you can use the previous snipped in your `Fastfile`.

And it will output something like this:

```ruby
# lib/fast/version.rb:4
VERSION = '0.1.2'
```

Create shortcuts with blocks that are able to introduce custom coding in
the scope of the `Fast` module

To bump a new version of your library for example you can type `fast .bump_version`
and add the snippet to your library fixing the filename.

```ruby
Fast.shortcut :bump_version do
  rewrite_file('(casgn nil VERSION (str _)', 'lib/fast/version.rb') do |node|
    target = node.children.last.loc.expression
    pieces = target.source.split(".").map(&:to_i)
    pieces.reverse.each_with_index do |fragment,i|
      if fragment < 9
        pieces[-(i+1)] = fragment +1
        break
      else
        pieces[-(i+1)] = 0
      end
    end
    replace(target, "'#{pieces.join(".")}'")
  end
end
```

You can find more examples in the [Fastfile](./Fastfile).

### Fast with Pry

You can use `--pry` to stop on a particular source node, and run Pry at that
location:

    fast '(block (send nil it))' spec --pry

Inside the pry session you can access `result` for the first result that was
located, or `results` to get all of the occurrences found.

Let's take a look at `results`:

    results.map { |e| e.children[0].children[2] }
    # => [s(:str, "parses ... as Find"),
    # s(:str, "parses $ as Capture"),
    # s(:str, "parses quoted values as strings"),
    # s(:str, "parses {} as Any"),
    # s(:str, "parses [] as All"), ...]

### Fast with RSpec

Let's say we wanted to get all the `it` blocks in our `RSpec` code that
currently do not have descriptions:

    fast '(block (send nil it (nil)) (args) (!str)) ) )' spec

This will return the following:

    # spec/fast_spec.rb:166
    it { expect(described_class).to be_match(s(:int, 1), '(...)') }
    # spec/fast_spec.rb:167
    it { expect(described_class).to be_match(s(:int, 1), '(_ _)') }
    # spec/fast_spec.rb:168
    it { expect(described_class).to be_match(code['"string"'], '(str "string")') }

## Experiments

Experiments can be used to run experiments against your code in an automated
fashion. These experiments can be used to test the effectiveness of things
like performance enhancements, or if a replacement piece of code actually works
or not.

Let's create an experiment to try and remove all `before` and `after` blocks
from our specs.

If the spec still pass we can confidently say that the hook is useless.

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

    bin/console
    code("a = 1") # => s(:lvasgn, s(:int, 1))

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jonatas/fast. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

See more on the [official documentation](https://jonatas.github.io/fast).
