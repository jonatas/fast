Fast is partially supporting SQL syntax. Behind the scenes it parses SQL using
[pg_query](https://github.com/pganalyze/pg_query) and simplifies it to AST Nodes
using the same Ruby interface.

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
