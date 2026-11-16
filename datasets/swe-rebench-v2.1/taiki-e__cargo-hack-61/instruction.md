Should --each-feature and --feature-powerset run --all-features?
default/no-default features are already included, so all-features also need to be included?

### Additional contract requirements

- `--each-feature` and `--feature-powerset` also run a final invocation with `--all-features`, in addition to the runs they already perform.
- Add a `--skip-all-features` CLI flag that skips the run with just `--all-features`.
- `--skip-all-features` can only be used together with `--each-feature` or `--feature-powerset`; using it without either is an error whose message is `--skip-all-features can only be used with either --each-feature or --feature-powerset`.
