Helm search should have the option to exit with 1 if no results found
`helm version`: `version.BuildInfo{Version:"v3.0.1", GitCommit:"7c22ef9ce89e0ebeb7125ba2ebf7d421f3e82ffa", GitTreeState:"clean", GoVersion:"go1.13.4"}`

`helm search repo` and `helm search hub` should have an option to exit with `1` when nothing is found. This is useful in automation scripts. Something like `--fail` or `--fail-if-no-results-found`.

### Additional contract requirements

- Expose this option as `--fail-on-no-result` for both `helm search repo` and `helm search hub`.
- For `helm search repo`, when `--fail-on-no-result` is set and no results are found, the error output must be `Error: no results found\n`.
- For `helm search hub`, when `--fail-on-no-result` is set and no results are found, the error output must be `Error: no results found\n`.
- When no results are found without this option, `helm search hub` must output `No results found\n` in table format and `[]\n` in JSON and YAML formats.
- When results are found, enabling `--fail-on-no-result` must not cause either search command to fail.
