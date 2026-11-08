refactor run function
the `run` function is bloated with conditional logic that makes it hard to read, we should refactor it by abstracting certain parts as separate functions, so it reads linearly and add any other changes that improve readability.

We should also add more unit tests since we've been touching this function a lot, since its the core function that runs SQL code, we should ensure good testing coverage

https://github.com/ploomber/jupysql/blob/924f237d1c97733211eeea2f37d521de841cbdcd/src/sql/run.py#L378

### Additional contract requirements

- Add a public function `is_postgres_or_redshift(dialect)` in module `sql.run`. It returns `True` when the string representation of `dialect` contains `"postgres"` or `"redshift"`, and `False` otherwise.
- Add a public function `handle_postgres_special(conn, statement)` in module `sql.run` that executes a PostgreSQL-specific command. It raises `ImportError` when the optional `pgspecial` module is unavailable.
- Add a public function `set_autocommit(conn, config)` in module `sql.run`. When `config.autocommit` is true it attempts to enable AUTOCOMMIT on the connection's session; if the driver does not support it, it logs a debug message containing the exact substring `The database driver doesn't support such ` and returns `True`. Otherwise it returns `False`.
- Add a public function `select_df_type(resultset, config)` in module `sql.run`. It returns a pandas DataFrame when `config.autopandas` is true, a polars DataFrame when `config.autopolars` is true and `config.autopandas` is false, and the `resultset` itself otherwise. If both flags are true, pandas takes precedence.
- Add a public function `interpret_rowcount(rowcount)` in module `sql.run`. It returns `"Done."` when `rowcount` is negative, and otherwise the string `"%d rows affected." % rowcount`.
- `run(conn, sql, config)` in module `sql.run` executes each statement in `sql` against `conn.session` and returns the result selected by `select_df_type` for the last statement. When `sql` is empty or whitespace only it returns `"Connected: %s" % conn.name`. When the first statement begins with `BEGIN` it raises `ValueError` whose message contains the exact phrase `does not support transactions`. When `config.feedback` is true it prints `interpret_rowcount(result.rowcount)` for each executed statement.
