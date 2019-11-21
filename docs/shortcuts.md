# Shortcuts

Shortcuts are defined on a `Fastfile` inside any ruby project.

!!!info "Use `~/Fastfile`"
    You can also add one extra in your `$HOME` if you want to have something loaded always.

By default, the command line interface does not load any `Fastfile` if the
first param is not a shortcut. It should start with `.`.

I'm building several researches and I'll make the examples open here to show
several interesting cases in action.

## Automated Refactor: Bump version

Let's start with a [real usage](https://github.com/jonatas/fast/blob/master/Fastfile#L20-L34)
to bump a new version of the gem.

```ruby
Fast.shortcut :bump_version do
  rewrite_file('(casgn nil VERSION (str _)', 'lib/fast/version.rb') do |node|
    target = node.children.last.loc.expression
    pieces = target.source.split('.').map(&:to_i)
    pieces.reverse.each_with_index do |fragment, i|
      if fragment < 9
        pieces[-(i + 1)] = fragment + 1
        break
      else
        pieces[-(i + 1)] = 0
      end
    end
    replace(target, "'#{pieces.join('.')}'")
  end
end
```

And then the change is done in the `lib/fast/version.rb`:

```diff 
module Fast
-  VERSION = '0.1.6'
+  VERSION = '0.1.7'
end
```

## List Shortcuts

As the interface is very rudimentar, let's build a shortcut to print what
shortcuts are available. This is a good one to your `$HOME/Fastfile`:

```ruby
# List all shortcut with comments
Fast.shortcut :shortcuts do
  fast_files.each do |file|
    lines = File.readlines(file).map{|line|line.chomp.gsub(/\s*#/,'').strip}
    result = capture_file('(send ... shortcut $(sym _', file)
    result = [result] unless result.is_a?Array
    result.each do |capture|
      target = capture.loc.expression
      puts "fast .#{target.source[1..-1].ljust(30)} # #{lines[target.line-2]}"
    end
  end
end
```

And using it on `fast` project that loads both `~/Fastfile` and the Fastfile from the project:

```
fast .version       # Let's say you'd like to show the version that is over the version file
fast .parser        # Simple shortcut that I used often to show how the expression parser works
fast .bump_version  # Use `fast .bump_version` to rewrite the version file
fast .shortcuts     # List all shortcut with comments
```

## RSpec: Find unused shared contexts

If you build shared contexts often, probably you can forget some left overs.

The objective of the shortcut is find leftovers from shared contexts.

First, the objective is capture all names of the `RSpec.shared_context` or
 `shared_context` declared in the `spec/support` folder.

```ruby
Fast.capture_all('(block (send {nil,_} shared_context (str $_)))', Fast.ruby_files_from('spec/support'))
```

Then, we need to check all the specs and search for `include_context` usages to
confirm if all defined contexts are being used:

```ruby
specs = Fast.ruby_files_from('spec').select{|f|f !~ %r{spec/support/}}
Fast.search_all("(send nil include_context (str #register_usage)", specs)
```

Note that we created a new reference to `#register_usage` and we need to define the method too:


```ruby
@used = []
def register_usage context_name
	@used << context_name
end
```

Wrapping up everything in a shortcut:

```ruby
# Show unused shared contexts
Fast.shortcut(:unused_shared_contexts) do
  puts "Checking shared contexts"
  Kernel.class_eval do
    @used = []
    def register_usage context_name
      @used << context_name
    end
    def show_report! defined_contexts
      unused = defined_contexts.values.flatten - @used
      if unused.any?
        puts "Unused shared contexts", unused
      else
        puts "Good job! all the #{defined_contexts.size} contexts are used!"
      end
    end
  end
  specs = ruby_files_from('spec/').select{|f|f !~ %r{spec/support/}}
  search_all("(send nil include_context (str #register_usage)", specs)
  defined_contexts = capture_all('(block (send {nil,_} shared_context (str $_)))', ruby_files_from('spec'))
  Kernel.public_send(:show_report!, defined_contexts)
end
```

!!! faq "Why `#register_usage` is defined on the `Kernel`?"
    Yes! note that the `#register_usage` was forced to be inside `Kernel`
    because of the `shortcut` block that takes the `Fast` context to be easy
    to access in the default functions. As I can define multiple shortcuts
    I don't want to polute my Kernel module with other methods that are not useful.


## RSpec: Remove unused let

!!! hint "First shortcut with experiments"
    If you're not familiar with automated experiments, you can read about it [here](/experiments).

The current scenario is similar in terms of search with the previous one, but more advanced
because we're going to introduce automated refactoring.

The idea is simple, if it finds a `let` in a RSpec scenario that is not referenced, it tries to experimentally remove the `let` and run the tests:

```ruby
# Experimental remove `let` that are not referenced in the spec
Fast.shortcut(:exp_remove_let) do
  require 'fast/experiment'
  Kernel.class_eval do
    file = ARGV.last

    defined_lets = Fast.capture_file('(block (send nil let (sym $_)))', file).uniq
    @unreferenced= defined_lets.select do |identifier|
      Fast.search_file("(send nil #{identifier})", file).empty?
    end

    def unreferenced_let?(identifier)
      @unreferenced.include? identifier
    end
  end

  experiment('RSpec/RemoveUnreferencedLet') do
    lookup ARGV.last
    search '(block (send nil let (sym #unreferenced_let?)))'
    edit { |node| remove(node.loc.expression) }
    policy { |new_file| system("bundle exec rspec --fail-fast #{new_file}") }
  end.run
end
```

And it will run with a single file from command line:

```
fast .exp_remove_let spec/my_file_spec.rb
```

