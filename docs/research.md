
# Research

I love to research about codebase as data and prototyping ideas several times
doesn't fit in simple [shortcuts](/shortcuts).

Here is my first research that worth sharing:

## Combining Runtime metadata with AST complex searches

This example covers how to find RSpec `allow` combined with `and_return` missing
the `with` clause specifying the nested parameters.

Here is the [gist](https://gist.github.com/jonatas/c1e580dcb74e20d4f2df4632ceb084ef)
if you want to go straight and run it.

Scenario for simple example:

Given I have the following class:

```ruby
class Account
  def withdraw(value)
    if @total >= value
      @total -= value
      :ok
    else
      :not_allowed
    end
  end
end
```

And I'm testing it with `allow` and some possibilities:

```ruby
# bad
allow(Account).to receive(:withdraw).and_return(:ok)
# good
allow(Account).to receive(:withdraw).with(100).and_return(:ok)
```

**Objective:** find all bad cases of **any** class that does not respect the method
parameters signature.

First, let's understand the method signature of a method:

```ruby
Account.instance_method(:withdraw).parameters
# => [[:req, :value]]
```

Now, we can build a small script to use the node pattern to match the proper
specs that are using such pattern and later visit their method signatures.


```ruby
Fast.class_eval do
  # Captures class and method name when find syntax like:
  # `allow(...).to receive(...)` that does not end with `.with(...)`
  pattern_with_captures = <<~FAST
  (send (send nil allow (const nil $_)) to
    (send (send nil receive (sym $_)) !with))
  FAST

  pattern = expression(pattern_with_captures.tr('$',''))

  ruby_files_from('spec').each do |file|
    results = search_file(pattern, file) || [] rescue next
    results.each do |n|
      clazz, method = capture(n, pattern_with_captures)
      if klazz = Object.const_get(clazz.to_s) rescue nil
        if klazz.respond_to?(method)
          params = klazz.method(method).parameters
          if params.any?{|e|e.first == :req}
            code = n.loc.expression
            range = [code.first_line, code.last_line].uniq.join(",")
            boom_message = "BOOM! #{clazz}.#{method} does not include the REQUIRED parameters!"
            puts boom_message, "#{file}:#{range}", code.source
          end
        end
      end
    end
  end
end
```

!!! hint "Preload your environment **before** run the script"

    Keep in mind that you should run it with your environment preloaded otherwise it
    will skip the classes.
    You can add elses for `const_get` and `respond_to` and report weird cases if
    your environment is not preloading properly.
