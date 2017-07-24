# Fast

[![Build Status](https://travis-ci.org/jonatas/fast.svg?branch=master)](https://travis-ci.org/jonatas/fast)

Fast is a "Find AST" tool to help you search in the code abstract syntax tree.

Ruby allow us to do the same thing in a few ways then it's hard to check
how the code is written.

The syntax is inspired on [RuboCop Node Pattern](https://github.com/bbatsov/rubocop/blob/master/lib/rubocop/node_pattern.rb).

To learn more about how AST works, you can install `ruby-parse` and check how is the AST of
your current code.

`ruby-parse my-file.rb`

It will output the AST representation.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ffast'
```

And then execute:

    $ bundle

Or install it yourself as:

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

Lets abstract a bit and allow any integer value using `_` as a shortcut:

```ruby
Fast.match?(ast, '(lvasgn value (int _))') # true
```

Lets abstract more and allow float or integer:

```ruby
Fast.match?(ast, '(lvasgn value ({float int} _))') # true
```

We can match "a node with children" using `...`:

```ruby
Fast.match?(ast, '(lvasgn value ...)') # true
```

Lets learn more about this shortcuts:

- `$` is for **capture**
- `_` is **something**
- `...` is a **node** with children

You can use `$` to capture a node:

```ruby
Fast.match?(ast, '(lvasgn value $...)') # => [s(:int, 42)]
```

Or match any local variable assignment combining both `_` and `...`:

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

You can search using sub-arrays with pure values or shortcuts:

```ruby
Fast.match?(ast, [:send, [:send, '...'], :d]) # => true
Fast.match?(ast, [:send, [:send, '...'], :c]) # => false
Fast.match?(ast, [:send, [:send, [:send, '...'], :c], :d]) # => true
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

## Search in files

It will also inject a executable named `fast` and you can use it to search and
find code using the concept:

```
$ fast '(def match?)' lib/fast.rb
```

- Use `-d` or `--debug` for enable debug mode.
- Use `--ast` to output the AST instead of the original code

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jonatas/fast. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

