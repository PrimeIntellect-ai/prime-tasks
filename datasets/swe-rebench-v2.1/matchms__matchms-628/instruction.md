Pipeline should be able to take in custum filters
SpectrumProcessor is able to handle custom filters, however, pipeline is not.
[HIDDEN] This works for the matchms filters, but does not work for the custom filters.

### Additional contract requirements

- `create_workflow` accepts, for both `query_filters` and `reference_filters`, elements that are a filter name (str), a raw callable filter function, or a `(callable, param_dict)` tuple pairing a callable filter with a dictionary of keyword arguments.
- A custom callable filter receives a spectrum and returns a spectrum or `None`; returning `None` removes that spectrum from the processed set.
- A `Pipeline` exposes a public `processing_queries` attribute with a `parse_and_add_filter(filter_entry)` method that accepts a `(callable, param_dict)` tuple and registers the custom filter so it is applied to the query spectra during the run.
