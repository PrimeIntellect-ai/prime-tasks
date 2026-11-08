[Enh]: add support for `.to_polars()`
# Description

We have `to_pandas`, `to_arrow`, `to_numpy`, all of which are supported in the polars API. Clearly polars does not need a `to_polars` method, but _maybe_ we could. I don't have a particular use case in mind as of now though, except for the interchange level support, which could decide which backend materialize the data into if needed.
