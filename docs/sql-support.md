# SQL Support

Fast supports SQL through [pg_query](https://github.com/pganalyze/pg_query), a powerful Ruby wrapper for the PostgreSQL SQL parser. 

By default, the SQL module is not loaded with the core library, but Fast auto-detects `.sql` file extensions. You can also explicitly instruct the command-line interface to parse SQL using the `--sql` flag.

```bash
fast --sql select_stmt /path/to/my-file.sql
```

## Abstract Syntax Trees for SQL

Abstract Syntax Trees (ASTs) represent code structure systematically. In Fast, building a node pattern helps you search and match SQL elements intelligently—moving beyond regular expressions!

Every AST node outputted via pg_query in Fast takes an s-expression format:

```ruby
Fast.parse_sql("SELECT 1")
# => s(:select_stmt,
#   s(:target_list,
#     s(:res_target,
#       s(:val,
#         s(:a_const,
#           s(:ival,
#             s(:ival, 1)))))))
```

### Searching SQL Snippets

Imagine you have a directory of example SQL snippets:

```bash
fast --sql '(relname "users")' sql-snippets/
```

This searches natively for table relations matching "users", ignoring instances where the string "users" appears as just a text value or comment.

## Building Advanced Linters 

One of the great powers of an AST represents contextual relationships. During development with TimescaleDB, for instance, you can use continuous aggregates (materialized views) to save on computation.

If you query a raw hypertable utilizing `time_bucket()`, you could likely achieve the same results by querying the continuous aggregate. We can check for this inefficiency with Fast!

First, identify the pattern of a target query:
```ruby
pattern = <<~FAST
  (select_stmt
    (target_list (res_target (val (func_call (funcname (string (sval "time_bucket"))) ...))))
    (from_clause (range_var (relname $_)))
FAST
```

By querying and recording all queries and all materialized views matching `CREATE MATERIALIZED VIEW`, you can map which queries can be directly substituted. You can build advanced checking capabilities into custom scripts simply relying on node interactions like `replace`.

## Formatting SQL

Need a formatter? Let's say you want to capitalize reserved keywords in your SQL string securely. A Fast script leveraging `Fast::SQL.replace` can walk the AST, targeting specific token metadata:

```ruby
Fast.shortcut :format_sql do
  require 'fast/sql'
  file = ARGV.last
  ast = Fast.parse_sql_file(file).first
  eligible_kw = [:RESERVED_KEYWORD]
  
  output = Fast::SQL.replace('_', ast) do |root|
    sb = root.loc.expression.source_buffer
    sb.tokens.each do |token|
      if eligible_kw.include?(token.keyword_kind)
        range = Fast::Source.range(sb, token.start, token.end)
        replace(range, range.source.upcase)
      end
    end
  end
  puts Fast.highlight(output, sql: true)
end
```

Run this with `fast .format_sql example.sql`!

## Anonymizing Data 

To scrub database schemas or protect anonymized table requests safely:

```ruby
Fast.shortcut :anonymize_sql do
  require 'fast/sql'
  ast = Fast.parse_sql_file(ARGV.last)
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

## Model Context Protocol (MCP)

To assist autonomous AI agents, IDEs, and editors with understanding your repository's SQL directly, Fast ships an MCP server out of the box with embedded SQL tools.

These standard MCP mechanisms allow robust reading and writing inside the workspace:

- `search_sql_ast`: Retrieve chunks of valid SQL matches via s-expressions (`(select_stmt ...)`).
- `rewrite_sql`: Run `Fast::SQL.replace` locally on fragments.
- `rewrite_sql_file`: Update SQL instructions reliably within `.sql` files on disk.

To use the server, add it to your configuration (like `claude_desktop_config.json`):
```json
"fast": {
  "command": "bundle",
  "args": ["exec", "fast-mcp"]
}
```

By providing these standard tool sets over MCP, any modern LLM client can interact intelligently with SQL ASTs immediately.
