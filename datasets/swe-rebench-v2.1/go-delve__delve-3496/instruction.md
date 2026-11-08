dap: consider []string for Launch BuildFlags
DAP [`LaunchConfig.BuildFlags`](https://github.com/go-delve/delve/blob/c7e2a9b6fb902d685e77b28b001c0c95e5eb95b3/service/dap/types.go#L101) is defined as `string` type.
It is `string` because VS Code Go defined the `buildFlags` in that way in its legacy debug adapter that invokes `dlv debug` or `dlv test`, and `dlv` command line takes the build flags (--build-flags) as a string.

DAP can take Launch configuration in JSON, which can support more rich types than a simple command line flag.
Historically, the subtle difference between how dlv is parsing the build flags and how go command is parsing the flags was annoying and sometimes frustrating (e.g. https://github.com/golang/vscode-go/issues/1027).

Please consider to take `[]string` and bypass delve's flag parsing.

### Additional contract requirements

DAP launch requests in both `debug` and `test` modes must accept `buildFlags` as either a string or an array of strings. For an array, every element is passed to the Go build or test command as its own argument, without Delve's string parsing. Other JSON value types are invalid.
