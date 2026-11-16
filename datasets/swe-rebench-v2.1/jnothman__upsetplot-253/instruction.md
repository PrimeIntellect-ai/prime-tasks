Specify maximum number of intersections to display
Hi,

Apologies if this has already been implemented, but after going through the [API documentation](https://upsetplot.readthedocs.io/en/stable/api.html), I'm unable to find an option that limits the number of displayed intersections, which forces me to manually truncate my dataframe I'm trying to plot from.

If you can point me to an argument that lets me do this that would be great. If this is not already implemented, it certainly would be useful!

Thanks!

### Additional contract requirements

- `UpSet` (class in module `upsetplot.plotting`, also exposed as `upsetplot.UpSet`) accepts a keyword argument `max_subset_rank` (int, optional). When supplied, it limits the intersections to the top N subsets ordered by descending computed subset size, including every subset tied at the N-th rank.
- The `max_subset_rank` option is accepted by `UpSet` and by the module-level `upsetplot.plot` entry point, and it limits the number of intersections displayed in the plot produced by `UpSet.plot` / `upsetplot.plot`.
- `UpSet.intersections` exposes the subset sizes after filtering, so it reflects the `max_subset_rank` limit.
