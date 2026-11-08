Support control over number of row groups as an option
When converting to GeoParquet it can be useful to set more row groups, for more efficient querying on large files. See https://github.com/opengeospatial/geoparquet/discussions/183

GDAL's is 'ROW_GROUP_SIZE=<integer>: Defaults to 65536. Maximum number of rows per group.'

Which seems reasonable, though I was doing like 20k default size for my experiments, so we could consider having the default be less - I didn't see negative effects, but something I read said if you have lots of parquet files then smaller row group size can affect the times of getting stats on the whole set. I think I have like 500 individual parquet files, so perhaps if it's thousands or tens of thousands it comes into effect?

### Additional contract requirements

When `convert` rewrites Parquet input to GeoParquet, `--row-group-length N` limits each output row group to at most N rows. The conversion preserves every input row exactly once.
