Can not use NOT IN in SELECT statements
`SELECT` statements do not accept the `NOT IN` syntax.

If a `SELECT` statement is like the following:

    SELECT foo
    FROM bar
    WHERE baz NOT IN ('qux', 'shme')

Then the parser issues an error like the following:

    Syntax error near baz not in
