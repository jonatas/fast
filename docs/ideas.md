# Ideas I want to build with Fast

I don't have all the time I need to develop all the ideas I have to build
around this tool, so here is a dump of a few brainstormings:

## Inline target code

I started [fast-inline](https://github.com/jonatas/fast-inline) that can be
useful to try to see how much every library is used in a project.

My idea is try to inline some specific method call to understand if it makes
sense to have an entire library in the stock.

Understanding dependencies and how the code works can be a first step to get an
"algorithm as a service". Instead of loading everything from the library, it
would facilitate the cherry pick of only the proper dependencies necessaries to
run the code you have and not the code that is overloading the project.

## Neo4J adapter

Easy pipe fast results to Neo4J. It would facilitate to explore more complex
scenarios and combine data from other sources.

## Ast Diff

Allow to compare and return a summary of differences between two trees.

It would be useful to identify renamings or other small changes, like only
changes in comments that does not affect the file and possibly be ignored for
some operations like run or not run tests.

## Transition synapses

Following the previous idea, it would be great if we can understand the
transition synapses and make it easily available to catch up with previous
learnings.

https://github.com/jonatas/chewy-diff/blob/master/lib/chewy/diff.rb

This example, shows adds and removals from specific node targets between two
different files.

If we start tracking AST transition synapses and associating with "Fixes" or
"Reverts" we can predict introduction of new bugs by inpecting if the
introduction of new patterns that can be possibly reverted or improved.

## Fast Rewriter with pure strings

As the AST rewriter adopts a custom block that needs to implement ruby code,
we can expand the a query language for rewriting files without need to take the
custom Ruby block.

Example:

```ruby
Fast.gsub_expression('remove(@expression)') # (node) => { remove(node.location.expression) }
```

And later we can bind it in the command line to allow implement custom
replacements without need to write a ruby file.

```
fast (def my_target_method) lib spec --rewrite "remove(@expression)"
```

or

```
fast (def my_target_method) lib spec --rewrite "replace(@name, 'renamed_method')"
```
