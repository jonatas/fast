# Command line

When you install the ffast gem, it will also create an executable named `fast` 
and you can use it to search and find code using the concept:

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
it { expect(described_class).to be_match('(...)', s(:int, 1)) }
...
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

See also [Code Similarity](similarity_tutorial.md) tutorial.

## `-c` to search from code example

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

## Fastfile

`Fastfile` will loaded when you start a pattern with a dot. It means the pattern
will be a shortcut predefined on these Fastfiles.

It will make three attempts to load `Fastfile` defined in `$PWD`, `$HOME` or
checking if the `$FAST_FILE_DIR` is configured.

You can define a `Fastfile` in any project with your custom shortcuts and easy
check some code or run some task.


## Shortcut examples

Create shortcuts with blocks enables introduce custom coding in
the scope of the `Fast` module.

### Print library version.

Let's say you'd like to show the version of your library. Your regular params
in the command line will look like:

    $ fast '(casgn nil VERSION)' lib/*/version.rb

It will output but the command is not very handy. In order to just say `fast .version`
you can use the previous snippet in your `Fastfile`.

```ruby
Fast.shortcut(:version, '(casgn nil VERSION)', 'lib/fast/version.rb')
```

And calling `fast .version` it will output something like this:

```ruby
# lib/fast/version.rb:4
VERSION = '0.1.2'
```

We can also always override the files params passing some other target file
like `fast .version lib/other/file.rb` and it will reuse the other arguments
from command line but replace the target files.

### Bumping a gem version

While releasing a new gem version, we always need to mechanical go through the
`lib/<your_gem>/version.rb` and change the string value to bump the version
of your library. It's pretty mechanical and here is an example that allow you 
to simple use `fast .bump_version`:

```ruby
Fast.shortcut :bump_version do
  rewrite_file('lib/fast/version.rb', '(casgn nil VERSION (str _)') do |node|
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

!!! note "Note the shortcut scope"
    The shortcut calls `rewrite_file` from `Fast` scope as it use
    `Fast.instance_exec` for shortcuts that yields blocks.

Checking the version:

```bash
$ fast .version                                                                                                                                                                                                                            13:58:40
# lib/fast/version.rb:4
VERSION = '0.1.2'
```
Bumping the version:

```bash
$ fast .bump_version                                                                                                                                                                                                                       13:58:43
```

No output because we don't print anything. Checking version again:

```bash
$ fast .version                                                                                                                                                                                                                            13:58:54
# lib/fast/version.rb:4
VERSION = '0.1.3'
```

And now a fancy shortcut to report the other shortcuts :)

```ruby
Fast.shortcut :shortcuts do
  report(shortcuts.keys)
end
```

Or we can make it a bit more friendly and also use Fast to process the shortcut
positions and pick the comment that each shortcut have in the previous line: 

```ruby
# List all shortcut with comments
Fast.shortcut :shortcuts do
  fast_files.each do |file|
    lines = File.readlines(file).map{|line|line.chomp.gsub(/\s*#/,'').strip}
    result = capture_file('(send ... shortcut $(sym _))', file)
    result = [result] unless result.is_a?Array
    result.each do |capture|
      target = capture.loc.expression
      puts "fast .#{target.source[1..-1].ljust(30)} # #{lines[target.line-2]}"
    end
  end
end
```

And it will be printing all loaded shortcuts with comments:

```
$ fast .shortcuts
fast .version                        # Let's say you'd like to show the version that is over the version file
fast .parser                         # Simple shortcut that I used often to show how the expression parser works
fast .bump_version                   # Use `fast .bump_version` to rewrite the version file
fast .shortcuts                      # List all shortcut with comments
```

You can find more examples in the [Fastfile](https://github.com/jonatas/fast/tree/master/Fastfile).

