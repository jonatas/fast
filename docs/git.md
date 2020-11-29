
You can overload the AST node with extra methods to get information from Git.

Let's start with some basic setup to reuse in the next examples:

## Git require

By default, this extension is not loaded in the fast environment, so you should
require it.

```ruby
require 'fast/git'
```


Then it will work with any AST node.

```ruby
ast = Fast.ast_from_file('lib/fast.rb')
```

## Log

First commit from git:

```ruby
ast.git_log.first.author.name # => "Jonatas Davi Paganini"
```

It uses [ruby-git](https://github.com/ruby-git/ruby-git#examples) gem, so all
methods are available:

```ruby
ast.git_log.since(Time.mktime(2019)).entries.map(&:message)
```

Counting commits per year:

```ruby
ast.git_log.entries.group_by{|t|t.date.year}.transform_values(&:size)
# => {2020=>4, 2019=>22, 2018=>4}
```

Counting commits per contributor:

```ruby
ast.git_log.entries.group_by{|t|t.author.name}.transform_values(&:size)
# => {"Jônatas Davi Paganini"=>29, ...}
```

Selecting last commit message:

```ruby
ast.last_commit.message # => "Add node extensions for extracting info from git (#21)"
```

Remote git URL:

```ruby
ast.remote_url  # => "git@github.com:jonatas/fast.git"
ast.project_url # => "https://github.com/jonatas/fast"
```

The `sha` from last commit:

```ruby
ast.sha # => "cd1c036b55ec1d41e5769ad73b282dd6429a90a6"
```

Pick a link from the files to master version:

```ruby
ast.link # => "https://github.com/jonatas/fast/blob/master/lib/fast.rb#L3-L776"
```

Getting permalink from current commit:

```ruby
ast.permalink # => "https://github.com/jonatas/fast/blob/cd1c036b55ec1d41e5769ad73b282dd6429a90a6/lib/fast.rb#L3-L776"
```

## Markdown link

Let's say you'd like to capture a list of class names that inherits the `Find`
class:

```ruby
puts ast.capture("(class $(const nil _) (const nil Find)").map(&:md_link).join("\n* ")
```

It will output the following links:

* [FindString](https://github.com/jonatas/fast/blob/master/lib/fast.rb#L485)
* [MethodCall](https://github.com/jonatas/fast/blob/master/lib/fast.rb#L496)
* [InstanceMethodCall](https://github.com/jonatas/fast/blob/master/lib/fast.rb#L507)
* [FindWithCapture](https://github.com/jonatas/fast/blob/master/lib/fast.rb#L524)
* [FindFromArgument](https://github.com/jonatas/fast/blob/master/lib/fast.rb#L551)
* [Capture](https://github.com/jonatas/fast/blob/master/lib/fast.rb#L598)
* [Parent](https://github.com/jonatas/fast/blob/master/lib/fast.rb#L622)
* [Any](https://github.com/jonatas/fast/blob/master/lib/fast.rb#L636)
* [All](https://github.com/jonatas/fast/blob/master/lib/fast.rb#L647)
* [Not](https://github.com/jonatas/fast/blob/master/lib/fast.rb#L659)
* [Maybe](https://github.com/jonatas/fast/blob/master/lib/fast.rb#L667)

## Permalink

If you need to get a permanent link to the code, use the `permalink` method:

```ruby
ast.search("(class (const nil _) (const nil Find)").map(&:permalink)
# => ["https://github.com/jonatas/fast/blob/cd1c036b55ec1d41e5769ad73b282dd6429a90a6/lib/fast.rb#L524-L541",
#     "https://github.com/jonatas/fast/blob/cd1c036b55ec1d41e5769ad73b282dd6429a90a6/lib/fast.rb#L551-L571", ...]
```


