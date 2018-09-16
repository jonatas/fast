# Command line

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

## `--pry`

    $ fast '(block (send nil it))' spec --pry

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

## `--debug`

This option will print all matching details while validating each node.

```
$ echo 'object.method' > sample.rb
$ fast -d '(send (send nil _) _)' sample.rb
```

It will bring details of the expression compiled and each node being validated:

```
Expression: f[send] [#<Fast::Find:0x00007f8c53047158 @token="send">, #<Fast::Find:0x00007f8c530470e0 @token="nil">, #<Fast::Find:0x00007f8c53047090 @token="_">] f[_]
send == (send
  (send nil :object) :method) # => true
f[send] == (send
  (send nil :object) :method) # => true
send == (send nil :object) # => true
f[send] == (send nil :object) # => true
 ==  # => true
f[nil] ==  # => true
#<Proc:0x00007f8c53057af8@/Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/gems/2.5.0/gems/ffast-0.0.2/lib/fast.rb:25 (lambda)> == object # => true
f[_] == object # => true
[#<Fast::Find:0x00007f8c53047158 @token="send">, #<Fast::Find:0x00007f8c530470e0 @token="nil">, #<Fast::Find:0x00007f8c53047090 @token="_">] == (send nil :object) # => true
#<Proc:0x00007f8c53057af8@/Users/jonatasdp/.rbenv/versions/2.5.1/lib/ruby/gems/2.5.0/gems/ffast-0.0.2/lib/fast.rb:25 (lambda)> == method # => true
f[_] == method # => true
# sample.rb:1
object.method
```

## `-s` for similarity

Sometimes you want to search for some similar code like `(send (send (send nil _) _) _)` and we could simply say `a.b.c`.

The option `-s` build an expression from the code ignoring final values.

    $ echo 'object.method' > sample.rb
    $ fast -s 'a.b' sample.rb

```ruby
# sample.rb:1
object.method
```

See also [Code Similarity](simi)ilarity_tutorial.md) tutorial.

# `-c` to search from code example

You can search  for the exact expression with `-c`

    $ fast -c 'object.method' sample.rb

```ruby
# sample.rb:1
object.method
```

Combining with `-d`, in the header you can see the generated expression.

```
$ fast -d -c 'object.method' sample.rb | head -n 3

The generated expression from AST was:
(send
  (send nil :object) :method)
```

