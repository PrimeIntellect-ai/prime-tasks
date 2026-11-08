Add support for logging to file
implement functionality for `LogFile` and `LogFileFormat`

### Additional contract requirements

- The logging package `github.com/cybertec-postgresql/pg_timetable/internal/log` exposes
  `Init(opts config.LoggingOpts) LoggerHookerIface`, where `config` is
  `github.com/cybertec-postgresql/pg_timetable/internal/config`.
- `config.LoggingOpts` has the string fields `LogLevel`, `LogFile` and `LogFileFormat`.
- When `LogFile` is non-empty, log records are written to the file at that path.
- `LogFileFormat` selects the format of the file log records and accepts the values `json` and `text`.
- An unrecognized `LogLevel` value results in the info level being used.
