`CREATE_INDEX` and `CREATE_INDEX_EXCLUSIVE` docs are not helpful
Hi! Thanks for working on this project.
Today I updated to v5 and got some new CI failures.

Here's my migration file: https://github.com/tough-dev-school/python-testing-homework/blob/master/server/apps/identity/migrations/0001_initial.py

It generate this warning:

```
(pictures, 0001_initial)... WARNING (cached)
        CREATE INDEX prolongs transaction, delaying lock release
```

It is not clear from the docs on how to fix this warning. This forced me to switch it off for now.

### Additional contract requirements

The linter must not report the `CREATE_INDEX` or `CREATE_INDEX_EXCLUSIVE` warnings for an index created on a table that was created earlier in the same transaction. Concretely, when the SQL statements of a transaction contain a `CREATE TABLE <table>` statement before the `CREATE INDEX ... ON <table>` statement, no warning must be emitted for that index. An index created on a table that is not created earlier in the transaction (for example a different table) must still be reported.

The documentation for the `CREATE_INDEX_EXCLUSIVE` code must explain that using the `CONCURRENTLY` clause does not address the issue.

The documentation for the `CREATE_INDEX` code must explain that creating an index with PostgreSQL's `CONCURRENTLY` option avoids the table-locking risk described by the warning.
