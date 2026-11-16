Optimize/improve  xclim ensemble stats utilities
There are currently functional versions of the following utilities but they could use improvement / polishing:
```python
xclim.utils.utils.create_ensemble()
xclim.utils.ensemble_percentiles()
xclim.utils.calc_percentiles_simple()
xclim.utils.calc_percentiles_blocks()
xclim.utils.calc_perc()
```
**Ideas to explore:**

For ensemble creation :
-  create dimension using IndexVariable  (instead of just a string) and make sure that it has attribute axis='E'.


**Try to achieve dask enabled percentile calculation (remove 'time_block' method):**

- try DataArray.reduce(np.nanpercentile, dim='realization') - Check performance (nanpercentile seems slow)

- use DataArray.apply(xclim.utils.calc_perc, dim='realization') - 'calc_perc' only applies nanpercentile where needed ... should technically be faster

### Additional contract requirements

- Percentile outputs retain the input variable's attributes other than `description`, and include a description identifying them as percentile outputs.
- Percentiles can be calculated from Dask-backed data even when the `realization` dimension spans multiple chunks. The `keep_chunk_size` option accepts `None`, `True`, or `False` to control chunk handling; these choices must not change the percentile values.
