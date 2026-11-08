Errors should show in command instead of output files when get a profile
If errors occur when we use `goc profile --output output.txt` to get a profile, we found that there is nothing warning on the terminal screen. But the errors appeared unexpectedly in the output file.

### Additional contract requirements

- `cover.Action.Profile` (obtained from `cover.NewWorker(host)`) must return a non-nil error when the registry center responds with a non-200 HTTP status.
- `goc profile --output output.txt` must report such a failure on the command line, including the registry center's response body, and must not write that error text into the output file.
