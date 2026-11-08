Errors are not propagated correctly in a DDL batch
A DDL batch that contains the following:
1. The first statement is executed correctly.
2. The second statement is executed, but contains an error.

The error from the second statement is not propagated correctly to the client by PGAdapter.
