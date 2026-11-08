[ENH] Wrap pandas string methods
# Brief Description

One thing that might be nice is to wrap all of the string methods such that they are now method-chainable.

If this could be done programmatically, that would be awesome. Otherwise, manually wrapping ones of interest, and building up a submodule of string method operations, would be a superb alternative.

# Example API

The example API can be found in [this notebook](https://github.com/ericmjl/pyjanitor/blob/dev/examples/notebooks/tidytuesday_20190423.ipynb).

### Additional contract requirements

Provide a method-chainable `DataFrame.process_text(column, string_function, *args, **kwargs)` operation. It applies the named pandas string operation to the specified existing column and returns the resulting DataFrame, allowing the returned frame to be chained with other DataFrame operations. Support pandas string operations including `split`, `cat`, `get`, `lower`, and `replace`, forwarding their arguments to the corresponding pandas string operation.
