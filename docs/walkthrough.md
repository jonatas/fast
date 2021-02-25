# Fast walkthrough

!!! note "This is the main interactive tutorial we have on `fast`. If you're reading it on the web, please consider also try it in the command line: `fast .intro` in the terminal to get a rapid pace on reading and testing on your own computer."

The objective here is give you some insights about how to use `ffast` gem in the
command line.

Let's start finding the main `fast.rb` file for the fast library:

```
$ gem which fast
```

And now, let's combine the previous expression that returns the path to the file
and take a quick look into the methods `match?` in the file using a regular grep:

```
$ grep "def match\?" $(gem which fast)
```

Boring results, no? The code here is not easy to digest because we just see a
fragment of the code block that we want.
Let's make it a bit more advanced with `grep -rn` to file name and line number:

```
$ grep -rn "def match\?" $(gem which fast)
```

Still hard to understand the scope of the search.

That's why fast exists! Now, let's take a look on how a method like this looks
like from the AST perspective. Let's use `ruby-parse` for it:

```
$ ruby-parse -e "def match?(node); end"
```

Now, let's make the same search with `fast` node pattern:

```
fast "(def match?)" $(gem which fast)
```

Wow! in this case you got all the `match?` methods, but you'd like to go one level upper
and understand the classes that implements the method with a single node as
argument. Let's first use `^` to jump into the parent:

```
fast "^(def match?)" $(gem which fast)
```

As you can see it still prints some `match?` methods that are not the ones that
we want, so, let's add a filter by the argument node `(args (arg node))`:

```
fast "(def match? (args (arg node)))" $(gem which fast)
```

Now, it looks closer to have some understanding of the scope, filtering only
methods that have the name `match?` and receive `node` as a parameter.

Now, let's do something different and find all methods that receives a `node` as
an argument:

```
fast "(def _ (args (arg node)))" $(gem which fast)
```

Looks like almost all of them are the `match?` and we can also skip the `match?`
methods negating the expression prefixing with `!`:

```
fast "(def !match? (args (arg node)))" $(gem which fast)
```

Let's move on and learn more about node pattern with the RuboCop project:

```
$ VISUAL=echo gem open rubocop
```

RuboCop contains `def_node_matcher` and `def_node_search`. Let's make a search
for both method names wrapping the query with `{}` selector:

```
fast "(send nil {def_node_matcher def_node_search})" $(VISUAL=echo gem open rubocop)
```

As you can see, node pattern is widely adopted in the cops to target code.
Rubocop contains a few projects with dedicated cops that can help you learn
more.

## How to automate refactor using AST

Moving towards to the code automation, the next step after finding some target code
is refactor and change the code behavior.

Let's imagine that we already found some code that we want to edit or remove. If
we get the AST we can also cherry-pick any fragment of the expression to be
replaced. As you can imagine, RuboCop also benefits from automatic refactoring
offering the `--autocorrect` option.

All the hardcore algorithms are in the [parser](https://github.com/whitequark/parser)
rewriter, but we can find a lot of great examples on RuboCop project searching
for the `autocorrect` method.

```
fast "(def autocorrect)" $(VISUAL=echo gem open rubocop)
```

Look that most part of the methods are just returning a lambda with a
corrector. Now, let's use the `--ast` to get familiar with the tree details for the
implementation:

```
fast --ast "(def autocorrect)" $(VISUAL=echo gem open rubocop)/lib/rubocop/cop/style
```

As we can see, we have a `(send (lvar corrector))` that is the interface that we
can get the most interesting calls to overwrite files:

```
fast "(send (lvar corrector)" $(VISUAL=echo gem open rubocop)
```


## That is all for now!

I hope you enjoyed to learn by example searching with fast. If you like it,
please [star the project](https://github.com/jonatas/fast/)!

You can also build your own tutorials simply using markdown files like I did
here, you can find this tutorial [here](https://github.com/jonatas/fast/tree/master/docs/walkthrough.md).


