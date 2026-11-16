Ability to group multiple features for the powerset
With an increasing number of features, the powerset inherently grows exponentially. As such, even the ability to group two features (dependencies in my case) together would provide a significant improvement in CI time. The use-case behind this is for features that are wholly unrelated and do not interact in any way. In my case, I have `serde` and `rand` implementations, but enabling one would never cause the other to fail. Because of this, having an option like `--group-features serde,rand` would be great. The flag could be passed multiple times to create multiple groups.

### Additional contract requirements

- `--group-features` may only be used together with `--feature-powerset`. Using it with any other mode (for example `--each-feature`) aborts parsing with the error message `--group-features can only be used together with --feature-powerset`.
- Each `--group-features` occurrence must name at least two features. A group that names a single feature aborts parsing with the error message `--group-features requires a list of two or more features separated by space or comma`.
- When `--ignore-unknown-features` is used without `--features`, `--include-features`, or `--group-features`, parsing aborts with the error message `--ignore-unknown-features can only be used together with --features, --include-features, or --group-features`.
