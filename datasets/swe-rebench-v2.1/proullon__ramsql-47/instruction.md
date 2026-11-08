Can not set column to NULL in UPDATE statements
The `UPDATE` statements do not allow setting columns to `NULL`.

If an `UPDATE` statement is like the following:

    UPDATE foo
	SET bar = NULL
	WHERE baz = 'qux'

Then the parser issues an error like the following:

    Syntax error near = null ,
