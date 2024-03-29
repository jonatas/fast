# SQL

Fast supports SQL and all parser efforts are done through pg_query which means
it's PostgreSQL dialect only.

## Parsing

```ruby
require 'fast/sql'
ast = Fast.parse_sql('select 1')
# => s(:select_stmt,
#     s(:target_list,
#       s(:res_target,
#         s(:val,
#           s(:a_const,
#             s(:val,
#               s(:integer,
#                 s(:ival, 1))))))))
```

## Why it's interesting to use AST for SQL?

Both SQL are available and do the same thing:

```sql
select * from customers
```

or

```sql
table customers
```

they have exactly the same objective but written down in very different syntax.

Give a try:

```ruby
Fast.parse_sql("select * from customers") == Fast.parse_sql("table customers") # => true
```

## Match

Use `match?` with your node pattern to traverse the abstract syntax tree.

```ruby
Fast.match?("(select_stmt ...)", ast) # => true
```

Use `$` to capture elements from the AST:

```ruby
Fast.match?("(select_stmt $...)", ast)
#  => [s(:target_list,
#    s(:res_target,
#      s(:val,
#        s(:a_const,
#          s(:val,
#            s(:integer,
#              s(:ival, 1)))))))]
```

You can dig deeper into the AST specifying nodes:

```ruby
Fast.match?("(select_stmt (target_list (res_target (val ($...)))))", ast)
# => [s(:a_const,
#     s(:val,
#       s(:integer,
#         s(:ival, 1))))]
```

And ignoring node types or values using `_`. Check all [syntax](/syntax) options.

```ruby
Fast.match?("(select_stmt (_ (_ (val ($...)))))", ast)
# => [s(:a_const,
#     s(:val,
#       s(:integer,
#         s(:ival, 1))))]
```

## Search directly from the AST

You can also search directly from nodes and keep digging:

```ruby
ast = Fast.parse_sql('select 1');
ast.search('ival') # => [s(:ival, s(:ival, 1))]
```

Use first to return the node directly:

```ruby
ast.first('(ival (ival _))')  #=> s(:ival, s(:ival, 1))
```

Combine the `capture` method with `$`:

```ruby
ast.capture('(ival (ival $_))') # => [1]
```

!!! warn "Be careful with AST structures"
    The AST structure may vary depending on the Postgresql and the pg_query version
    used in the parser.


# Examples

Let's dive into a more complex example capturing fields and from clause of a
condition. Let's start parsing the sql:

## Capturing fields and where clause


```ruby
ast = Fast.parse_sql('select name from customer')
#   => s(:select_stmt,
#     s(:target_list,
#       s(:res_target,
#         s(:val,
#           s(:column_ref,
#             s(:fields,
#               s(:string,
#                 s(:str, "name"))))))),
#     s(:from_clause,
#       s(:range_var,
#         s(:relname, "customer"),
#         s(:inh, true),
#         s(:relpersistence, "p"))))
```

Now, let's build the expression to get the fields and from_clause.

```ruby
 cols_and_from = "
   (select_stmt
     (target_list (res_target (val (column_ref (fields $...)))))
     (from_clause (range_var $(relname _))))
"
```

Now, we can use `Fast.capture` or `Fast.match?` to extract the values from the
AST.

```ruby
Fast.capture(cols_and_from, ast)
# => [s(:string,
#     s(:str, "name")), s(:relname, "customer")]
```

## Search inside

```ruby
relname = Fast.parse_sql('select name from customer').search('relname').first
# => s(:relname, "customer")
```

Find the location of a node.

```ruby
relname.location # => #<Parser::Source::Map:0x00007fd3bcb0b7f0
#  @expression=#<Parser::Source::Range (sql) 17...25>,
#  @node=s(:relname, "customer")>
```

The location can be useful to allow you to do refactorings and find specific
delimitations of objects in the string.

The attribute `expression` gives access to the source range.

```ruby
relname.location.expression
# => #<Parser::Source::Range (sql) 17...25>
```

The `source_buffer` is shared and can be accessed through the expression.

```ruby
relname.location.expression.source_buffer
# => #<Fast::SQL::SourceBuffer:0x00007fd3bc2a6420
#    @name="(sql)",
#    @source="select name from customer",
#    @tokens=
#     [<PgQuery::ScanToken: start: 0, end: 6, token: :SELECT, keyword_kind: :RESERVED_KEYWORD>,
#      <PgQuery::ScanToken: start: 7, end: 11, token: :NAME_P, keyword_kind: :UNRESERVED_KEYWORD>,
#      <PgQuery::ScanToken: start: 12, end: 16, token: :FROM, keyword_kind: :RESERVED_KEYWORD>,
#      <PgQuery::ScanToken: start: 17, end: 25, token: :IDENT, keyword_kind: :NO_KEYWORD>]>
```

The tokens are useful to find the proper node location during the build but
they're not available for all the nodes, so, it can be very handy as an extra
reference.

## Replace

Replace fragments of your SQL based on AST can also be done with all the work
inherited from Parser::TreeRewriter components.

```ruby
Fast.parse_sql('select 1').replace('ival', '2') # => "select 2"
```

The previous example is a syntax sugar for the following code:

```ruby
Fast.replace_sql('ival',
  Fast.parse_sql('select 1'),
  &->(node){ replace(node.location.expression, '2') }
) # => "select 2"
```

The last argument is a proc that runs on the [parser tree rewriter](https://www.rubydoc.info/gems/parser/Parser/TreeRewriter
) scope.

Let's break down the previous code:

```ruby
ast = Fast.parse_sql("select 1")
#  => s(:select_stmt,
#    s(:target_list,
#      s(:res_target,
#        s(:val,
#          s(:a_const,
#            s(:ival,
#              s(:ival, 1)))))))
```

The pattern is simply matching node type that is `ival` but it could be a complex expression
like `(val (a_const (val (ival (ival _)))))`.

Completing the example:

```ruby
 Fast.replace_sql("ival", ast, &-> (n) { replace(n.loc.expression, "3") })
 # => "select 3"
```

`loc` is a shortcut for `location` attribute.


# Mastering on command line

Installing the gem ffast will allow you to use the `fast` utility in the command
line.

## Force sql

Fast can guess that `fast ... *.sql` is looking for SQL stuff. But, if your file
extension is not available or you want test something inline, use `--sql`.

    fast --sql --debug --similar "drop view _"

It will output

    Search similar to (drop_stmt (objects (list (items (string (sval _))))) (remove_type _) (behavior _))

## Similar

Generalize identifiers with `--similar`. It can be very useful to build the expression from SQL and
look for similar expressions.

    fast --sql --similar "select * from _" *.sql

You can also use `--debug` to check the expression

    fast --debug --sql --similar "select * from _"

Outputs:

```
Search similar to (select_stmt (target_list (res_target (val (column_ref (fields))))) (from_clause (range_var (relname _) (inh ) (relpersistence _))))
```

## From code

If you don't know the AST but wants an exact match from code, use `--from-code`
and it will build an expression that matches exactly the same tree.

```bash
fast --sql --from-code "select * from my_table" *.sql
```

## Reusing your patterns and statements

Check out the [Shortcuts](/sql/shortcuts).

