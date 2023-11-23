# Shortcuts

The `fast` CLI also supports shortcuts which are mapping expressions starting
with `.`.

Shortcuts can keep your abstract scripts organized. Let's say you
want to create your own format sql and you'll run it very often. You can create
a shortcut for it and just reuse as you need.

## Format SQL

Let's say you want to format some sql, so, here are some possible syntax to get
some formatted version of an inline code:

```
fast .format_sql "select * from tbl"
```

It should return "SELECT * FROM tbl" with all reserved keywords upcased. Even
it's not mandatory, it makes it much clear to scan the text.

The second option is with a sql file.

```
fast .format_sql /path/to/my_file.sql
```
Both cases will just output in the command line and further commands can be
combined to send it to another file.


Add the following script to your `Fastfile` to just get started:

```ruby
Fast.shortcut :format_sql do
  require 'fast/sql'
  content = ARGV.last
  method = File.exist?(content) ? :parse_sql_file : :parse_sql
  ast = Fast.public_send(method, content)
  ast = ast.first if ast.is_a? Array

  output = Fast::SQL.replace('_', ast) do |root|
    sb = root.loc.expression.source_buffer
    sb.tokens.each do |token|
      if token.keyword_kind == :RESERVED_KEYWORD
        range = Parser::Source::Range.new(sb, token.start, token.end)
        replace(range, range.source.upcase)
      end
    end
  end
  require 'fast/cli'
  puts Fast.highlight(output, sql: true)
end
```

# Anonymize SQL

Read a full [blog post](https://ideia.me/anonymize-sql) about this shortcut.

```ruby
# fast .anonymize_sql file.sql
Fast.shortcut :anonymize_sql do
  require 'fast/sql'
  file = ARGV.last
  ast = Fast.parse_sql_file(file)
  memo = {}

  relnames = search("(relname $_)", ast).grep(String).uniq
  pattern = "{relname (sval {#{relnames.map(&:inspect).join(' ')}})}"

  content = Fast::SQL.replace(pattern, ast) do |node|
    new_name = memo[node.source.tr(%|"'|, '')] ||= "x#{memo.size}"
    new_name = "'#{new_name}'" if node.type == :sval
    replace(node.loc.expression, new_name)
  end
  puts Fast.highlight(content, sql: true)
end
```

 Check out the default [shortcuts](/shortcuts) guide if you need more content
 about shortcuts.
