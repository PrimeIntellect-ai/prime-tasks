DEPR: observed=False default for DataFrame.pivot_table
This will keep the default in line with groupby from #43999

### Additional contract requirements

- `DataFrame.pivot_table` and the module-level `pandas.pivot_table` accept an `observed` argument whose default is `lib.no_default`.
- When `observed` is omitted and any of the groupers is categorical, a `FutureWarning` is emitted advising that the default will change to `True` in a future pandas release.
