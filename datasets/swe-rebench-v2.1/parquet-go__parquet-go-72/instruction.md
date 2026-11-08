Merging row groups throws panic when rows from one group are empty
Merging multiple sorted row groups will throw a panic when one of the groups returns empty rows during `ReadRows`, even if `n` is correctly returned as 0. The reason why we sometimes return empty rows is because we apply filtering during the merge process, and occasionally no rows will match the filter. I think this only happens when the entire row group is empty.

Here is a PR reproducing the issue: https://github.com/parquet-go/parquet-go/pull/67.
