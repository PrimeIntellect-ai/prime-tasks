Deadlock if BeginTx called with unexpected options
**Describe the bug**
If `BeginTx` (or `BeginTxFunc`) is called with unexpected options, `ExpectationsWereMet` deadlocks if called afterwards.

**To Reproduce**
In the example use `db.BeginTx(context.Background(), pgx.TxOptions{IsoLevel: pgx.Serializable})` instead of `db.Begin` (requires adding `BeginTx(context.Context, pgx.TxOptions) (pgx.Tx, error)` to the `PgxIface`). Run tests.

**Expected behavior**
Error return from `ExpectationsWereMet`

**Additional context**
The problem seems to be here:
https://github.com/pashagolub/pgxmock/blob/ed5a9231a38dd0b59bdd522ea1ba7b6df71a85a0/pgxmock.go#L513-L517
[HIDDEN]
