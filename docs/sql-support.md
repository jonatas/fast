# SQL Support
Fast is partially supporting SQL syntax. Behind the scenes it parses SQL using
[pg_query](https://github.com/pganalyze/pg_query) and simplifies it to AST Nodes
using the same Ruby interface. It's using Postgresql parser behind the scenes,
but probably could be useful for other SQL similar diallects .

The plan is that Fast would auto-detect file extensions and choose the sql path
in case the file relates to sql.

By default, this module is not included into the main library as it still very
experimental.

```ruby
require 'fast/sql'
```

# Parsing a sql content

```ruby
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

Use `match?` with your node pattern to traverse the abstract syntax tree.

```ruby
 Fast.match?("(select_stmt ...)", ast) # => true
```

Use `$` to capture elements from the AST:

```ruby
 Fast.match?("(select_stmt $...)", ast)
=> [s(:target_list,
  s(:res_target,
    s(:val,
      s(:a_const,
        s(:val,
          s(:integer,
            s(:ival, 1)))))))]

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

# Examples

## Capturing fields and where clause

Let's dive into a more complex example capturing fields and from clause of a
condition. Let's start parsing the sql:

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
#            s(:val,
#              s(:integer,
#                s(:ival, 1))))))))
```

The pattern is simply matching node type that is `ival` but it could be a complex expression
like `(val (a_const (val (integer (ival _)))))`.

Completing the example:

```ruby
 Fast.replace_sql("ival", ast, &-> (n) { replace(n.loc.expression, "3") })
 # => "select 3"
```

`loc` is a shortcut for `location` attribute.


