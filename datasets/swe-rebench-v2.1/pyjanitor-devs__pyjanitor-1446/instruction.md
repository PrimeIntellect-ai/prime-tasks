extend the `select` function to `pd.Series`
At the moment, `jn.select` applies only to DataFrames. Extending to pd.Series would be handy, especially when selecting MultiIndexes.

### Additional contract requirements

For a Series, `select` should retain the selector forms and selection controls available for DataFrame index selection. This includes positional selectors, inversion, and leaving the Series unchanged when no selector is supplied.
