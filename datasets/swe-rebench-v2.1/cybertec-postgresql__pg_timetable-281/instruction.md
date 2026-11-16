Add --log-database-level command-line parameter
Verbosity level for database storing. One can set the general log level to `DEBUG` for stdout and log file, but be less verbose for database destination.

### Additional contract requirements

- The `--log-database-level` command-line parameter selects the verbosity for database logging independently of the stdout/log-file level. It accepts the values `debug`, `info` and `error`, and defaults to `info`.
- Add a public function `NewHook(ctx context.Context, db PgxPoolIface, client string, cacheLimit int, level string) *LogHook` in package `internal/pgengine` that creates the database log hook configured with the given database log level.
- The public method `(*LogHook).Levels() []logrus.Level` returns the log levels the hook accepts, according to the configured database log level:
  - `debug`: all levels.
  - `info`: `info` and more severe levels; `debug` and `trace` entries are not accepted.
  - `error`: `error` and more severe levels; `warn`, `info`, `debug` and `trace` entries are not accepted.
