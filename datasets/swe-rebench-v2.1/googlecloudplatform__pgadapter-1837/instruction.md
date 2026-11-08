Connection ends up in ABORTED state after a failed COMMIT
If a `COMMIT` or a `ROLLBACK` fails, the connection is put into the `ABORTED` state. This requires the client application to execute a `ROLLBACK` before a new transaction can be executed. This is not consistent with real PostgreSQL, which puts the connection in the `IDLE` state if a  `COMMIT` or  `ROLLBACK` fails.
