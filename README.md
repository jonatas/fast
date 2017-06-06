# Fast

[![Build Status](https://travis-ci.org/jonatas/fast.svg?branch=master)](https://travis-ci.org/jonatas/fast)

Fast is a "Find AST" tool to help you search in the code abstract syntax tree.

It's inspired on [RuboCop Node Pattern](https://github.com/bbatsov/rubocop/blob/master/lib/rubocop/node_pattern.rb).

To learn more about how AST works, you can install `ruby-parse` and check how is the AST of
your current code.

`ruby-parse my-file.rb`

It will output the AST representation.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'fast'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install fast

## Usage

The idea is search in abstract tree using a simple expression build with an array:

The following code:

```ruby
a += 1
```

Generates the following AST representation:

```ruby
ast =
  s(:op_asgn,
    s(:lvasgn, :a),
    :+,
    s(:int, 1)
  )
```

Basically `s` represents `Parser::AST::Node` and the node has a `#type` and `#children`.

You can try to search by nodes that is using `:op_asgn` with some children using `...`:

```ruby
Fast.match?(ast, [:op_asgn, '...']) # => true
```

You can also check if the element is not nil with `_`:

```ruby
Fast.match?(ast, [:op_asgn, '_', '_', '_'])) # => true
```

You can go deeply with the arrays. Let's suppose we have a hardcore call to
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

You can search using sub-arrays in the same way:

```ruby
Fast.match?(ast, [:send, [:send, '...'], :d]) # => true
Fast.match?(ast, [:send, [:send, '...'], :c]) # => false
Fast.match?(ast, [:send, [:send, [:send, '...'], :c], :d]) # => true
```

It also knows how to parse strings:

```ruby
ast        = s(:send, s(:send, s(:send, nil, :a), :b), :c)
expression = '(send (send (send nil $_) $_) $_)'
Fast.match?(ast, expression)) # => [:a,:b,:c]
```

It will also inject a executable named `fast` and you can use it to search and
find code by this kind of expression

```
$ fast '(:def :match_node? _ )' lib/*.rb                                                                                                              20:36:21
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jonatas/fast. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

