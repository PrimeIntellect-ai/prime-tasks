"Insufficient data to process the guess" doesn't show up without `--debug`
as in the title, when there's not enough data to guess, the error doesn't show up without debug - it just prints `1 error`

### Additional contract requirements

- When a download encounters insufficient guess data, display an explanatory error containing `Insufficient data to process the guess` when verbose mode (`-v`) is enabled, even if `--debug` is not enabled; do not show only an aggregate error count.
