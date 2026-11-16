PERF: add_suffix and add_prefix shouldn't map partitions
### Describe the problem
`add_suffix` and `add_prefix` call the modin frame's `rename`, which [maps all blocks](https://github.com/modin-project/modin/blob/49f47b1ed66583d4b90d3c06faf3e1d457cf4df8/modin/core/dataframe/pandas/dataframe/dataframe.py#L1719). [HIDDEN]

### Additional contract requirements

- `Series.add_prefix` and `Series.add_suffix` must return the same labels pandas returns, and must not apply a function to every data partition of the underlying frame; only the labels should change.
