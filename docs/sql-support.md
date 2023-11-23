# SQL Support

Fast supports SQL through
[pg_query](https://github.com/pganalyze/pg_query) 
which is a Ruby wrapper for the Postgresql SQL parser.

By default, this module is not included into the main library.

Fast can auto-detect file extensions and choose the sql path in case the
file relates to sql. You can also use `--sql` in the command line to 
force the decision for the SQL parser.

    fast --sql select_stmt /path/to/my-file

The command line tool should be compatible with most of the commands.

To dive into all parsing steps, check out the [SQL](/sql/) section.

