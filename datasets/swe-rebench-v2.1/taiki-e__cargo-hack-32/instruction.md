request: Add enumeration diagnostics to output
When using --each-feature or --feature-powerset, its not often clear where the progress is in the overall scheme of things.

It would be nice if these flags added diagnostic info showing something like:

```
info: `cargo hack --each-feature` target 4 of 10
```
```
info: `cargo hack --each-feature` target 4 of 300
```

### Additional contract requirements

- For `--each-feature` and `--feature-powerset`, append ` (<current>/<total>)` to each existing `running ... on ...` diagnostic in stderr. `<current>` is the 1-based run number, and `<total>` is the total number of runs across the selected packages; for example: `running `cargo check` on real (1/5)`.
