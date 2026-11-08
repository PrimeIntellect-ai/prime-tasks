Upgrade to CEL 0.17
We need to replace uses of some of the deprecated functions and members but that's pretty trivial.

All tests pass except for partial evaluation of `now() > timestamp("2021-04-20") && R.attr.geo in ["GB", "US"]`. There's a small bug in the CEL library (https://github.com/google/cel-go/issues/785) but even with that bug fixed, we might not get the expected result from the new CEL version. It would return `timestamp("CURRENT_TIMESTAMP") > timestamp("2021-04-20") && R.attr.geo in ["GB", "US"]` rather than the expected result of `R.attr.geo in ["GB", "US"]`.

### Additional contract requirements

- The partial-evaluation expression uses a valid RFC 3339 timestamp literal: `now() > timestamp("2021-04-20T00:00:00Z") && R.attr.geo in ["GB", "US"]`. Partial evaluation of this expression must produce the residual `R.attr.geo in ["GB", "US"]`.
- The exported standard CEL environment `conditions.StdEnv` (in the `internal/conditions` package) provides a method `CELTypeAdapter()` that returns the CEL type adapter. The returned adapter provides `NativeToValue(value interface{}) ref.Val`, which converts a native Go value into a CEL reference value (`ref.Val` from `github.com/google/cel-go/common/types/ref`).
