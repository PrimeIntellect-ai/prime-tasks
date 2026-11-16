Add something like `--show-unmatched` to display files which have not matched any formatters
By default this is displayed at debug level. Perhaps if the flag was specified they should be displayed at a higher level or maybe even warn.

### Additional contract requirements

- The flag is named `--on-unmatched` with short alias `-u`. It accepts one of the log levels `debug`, `info`, `warn`, `error`, `fatal`.
- This contract supersedes the base text's debug-level default: when the flag is not specified, the level is `warn`.
- For each unmatched file reached before the command stops, a log line is emitted at the configured level in exactly this form:

      <LEVEL> format: no formatter for path: <absolute-path>

  where `<LEVEL>` is the charmbracelet/log level prefix: `DEBU`, `INFO`, `WARN`, `ERRO`, or `FATA`, and `<absolute-path>` is the file's absolute path.
- When the level is `fatal`, the command emits the line for the first unmatched path only, stops there, and returns an error whose message contains `no formatter for path: <absolute-path>`.
