# Experiments

Experiments allow us to play with AST and do some code transformation, execute
some code and continue combining successful transformations.

The major idea is try a new approach without any promise and if it works
continue transforming the code.

## Replace `FactoryBot#create` with `build_stubbed`.

Let's look into the following spec example:

```ruby
describe "my spec" do
  let(:user) { create(:user) }
  let(:address) { create(:address) }
  # ...
end
```

Let's say we're amazed with `FactoryBot#build_stubbed` and want to build a small
bot to make the changes in a entire code base. Skip some database
touches while testing huge test suites are always a good idea.

First we can hunt for the cases we want to find:

```
$ ruby-parse -e "create(:user)"
(send nil :create
  (sym :user))
```

Using `fast` in the command line to see real examples in the `spec` folder:

```
$ fast "(send nil create)" spec
```

If you don't have a real project but want to test, just create a sample ruby
file with the code example above.

Running it in a big codebase will probably find a few examples of blocks.

The next step is build a replacement of each independent occurrence to use
`build_stubbed` instead of create and combine the successful ones, run again and
combine again, until try all kind of successful replacements combined.

Considering we have the following code in `sample_spec.rb`:

```ruby
describe "my spec" do
  let(:user) { create(:user) }
  let(:address) { create(:address) }
  # ...
end
```

Let's create the experiment that will contain the nodes that are target to be
executed and what we want to do when we find the node.

```ruby
experiment = Fast.experiment('RSpec/ReplaceCreateWithBuildStubbed') do
  search '(send nil create)'
  edit { |node| replace(node.loc.selector, 'build_stubbed') }
end
```

If we use `Fast.replace_file` it will replace all occurrences in the same run
and that's one of the motivations behind create the `ExperimentFile` class.

Executing a partial replacement of the first occurrence:

```ruby
experiment_file = Fast::ExperimentFile.new('sample_spec.rb', experiment) }
puts experiment_file.partial_replace(1)
```

The command will output the following code:

```ruby
describe "my spec" do
  let(:user) { build_stubbed(:user) }
  let(:address) { create(:address) }
  # ...
end
```

## Remove useless before block

Imagine the following code sample:

```ruby
describe "my spec" do
  before { create(:user) }
  # ...
  after { User.delete_all }
end
```

And now, we can define an experiment that removes the entire code block and run
the experimental specs.

```ruby
experiment = Fast.experiment('RSpec/RemoveUselessBeforeAfterHook') do
  lookup 'spec'
  search '(block (send nil {before after}))'
  edit { |node| remove(node.loc.expression) }
  policy { |new_file| system("bin/spring rspec --fail-fast #{new_file}") }
end
```

To run the experiment you can simply say:

```ruby
experiment.run
```

Or drop the code into `experiments` folder and use the `fast-experiment` command
line tool.

    $ fast-experiment RSpec/RemoveUselessBeforeAfterHook spec
 
## DSL

- In the `lookup` you can pass files or folders.
- The `search` contains the expression you want to match
- With `edit` block you can apply the code change
- And the `policy` is executed to check if the current change is valuable

If the file contains multiple `before` or `after` blocks, each removal will
occur independently and the successfull removals will be combined as a
secondary change. The process repeates until find all possible combinations.

See more examples in [experiments](experiments) folder.

To run multiple experiments, use `fast-experiment` runner:

```
fast-experiment <experiment-names> <files-or-folders>
```

You can limit experiments or file escope:

```
fast-experiment RSpec/RemoveUselessBeforeAfterHook spec/models/**/*_spec.rb
```

