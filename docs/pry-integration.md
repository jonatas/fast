
You can create a custom command in pry to reuse fast in any session.

Start simply dropping it on your `.pryrc`:

```ruby
Pry::Commands.block_command "fast", "Fast search" do |expression, file|
  require "fast"
	files = Fast.ruby_files_from(file || '.')
  files.each do |f|
     results = Fast.search_file(expression, f)
		 next if results.nil? || results.empty?
     output.puts Fast.highlight("# #{f}")

     results.each do |result|
       output.puts Fast.highlight(result)
     end
  end
end
```

And use it in the console:

```pry
fast '(def match?)' lib/fast.rb
```

