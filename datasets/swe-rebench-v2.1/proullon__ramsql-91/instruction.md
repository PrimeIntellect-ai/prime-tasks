Primary Key Constraint Implementation
Our team stumbled upon the fact that the PK Constraint us supported in the parser but not the implementation this week.

We were hoping to get the PK Constraint implemented.

I was thinking of taking a crack at the feature myself in a fork. But, looking at the internals of how in `engine/agnostic/transaction.go Insert()` method, I am not sure I understand enough of aboout the ramsql data model to know what the correct PK constraint logic should be.

Can any of the contributors give me a good starting place/explanation for understanding how the PK logic should work?

### Additional contract requirements

- A `CREATE TABLE` statement may declare a primary key inline on a column or as a trailing `PRIMARY KEY (col1, col2, ...)` clause listing one or more columns.
- An `INSERT` that would create a row whose primary-key column values duplicate those of an existing row in the same table must fail with an error; inserts whose primary-key values are distinct must succeed.
