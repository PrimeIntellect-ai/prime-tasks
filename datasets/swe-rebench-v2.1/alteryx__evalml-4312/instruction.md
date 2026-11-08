Holdout data splitter creates NaN values with multiseries datasets

### Additional contract requirements

`evalml.preprocessing.split_data(X, y, problem_type, problem_configuration=None, test_size=None, random_seed=0)` splits feature and target data into training and hold-out portions and returns `(X_train, X_test, y_train, y_test)`.

For standard problems (binary, multiclass, regression and single-series time series) it behaves like a conventional hold-out splitter. When `test_size` is not given it defaults to `0.2` for non-time-series problems and `0.1` for time-series problems.

For multiseries time-series problems, `split_data` distinguishes stacked data (a single `pd.Series` target) from unstacked data (a `pd.DataFrame` target):

- For stacked multiseries data, `problem_configuration` is required and must contain both `"series_id"` and `"time_index"`. The resulting split is the same as the one produced by `split_multiseries_data(X, y, series_id, time_index)`, the feature splits are `pd.DataFrame` objects and the target splits are `pd.Series` objects.
- For unstacked multiseries data, `split_data` behaves like a conventional hold-out splitter and does not require `problem_configuration`; both the feature and target splits are `pd.DataFrame` objects.

Error conditions for stacked multiseries data:

- If `problem_configuration` is `None`, raise `ValueError("split_data requires problem_configuration for multiseries problems")`.
- If `problem_configuration` is missing either `"series_id"` or `"time_index"`, raise `ValueError("split_data needs both series_id and time_index values in the problem_configuration to split multiseries data")`.
