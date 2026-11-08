Add config option to allow output to specific file, e.g. `--output-file`
This will allow for better integration in situations like #302, without requiring a shell in the container image.

### Additional contract requirements

- The `-O` short flag must also be supported as an alias for `--output-file`.
- When the output-file path's containing directory does not exist, the command must exit with status code `1`.
- The `Config` struct in package `pkg/config` must expose an `OutputFile string` field, populated from the `--output-file`/`-O` flag.
- Add a public function `NewPrinter(choice string, outputFileName string) (Printer, error)` in package `pkg/printer` that returns a printer for the requested format (`json` or `text`) writing to the given output file, where `-` selects stdout, or an error if the format is unknown or the output file cannot be opened.
- The `Printer` interface in package `pkg/printer` must expose `Print([]judge.Result) error` and `Close() error`, where `judge.Result` is `github.com/doitintl/kube-no-trouble/pkg/judge.Result`.
- Closing a printer that writes to a file must close that file; closing a printer that writes to stdout must leave stdout open.
