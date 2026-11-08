Make box plot low/high indices/values optional to return
In a series with many outliers, returning all of the low and high indices and the low and high values can make the results of `box_plot_dict` difficult to read, as the low bound, the high bound, and the quantiles are such small parts of the output in that case.

We should add a parameter to `series.ww.box_plot_dict` that makes the inclusion of `low_indices`, `high_indices`, `low_values`, and `high_values` in the resulting dictionary optional, defaulting to including them in the returned dictionary.

```
# To avoid getting the indices and values returned set the parameter to False
series.ww.box_plot_dict(include_indices_and_values=False)
# defaults to True - if no parameter is passed in, returns the indices and values
series.ww.box_plot_dict()
```
