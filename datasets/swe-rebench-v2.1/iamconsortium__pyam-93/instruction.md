IamDataFrame constructor should take pd.DataFrame with index
Currently, the `IamDataFrame.__init__()` can take a `pd.DataFrame` with columns `['model', 'scenario' , ...]`, but it fails if these identifiers are given as an index.

This would be a nice-to-have feature so that the `pd.DataFrame` returned by the `timeseries()` function can be turned back into an `IamDataFrame`. This currently requires a `reset_index()`.
