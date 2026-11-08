should `LazyFrame.schema` issue a performance warning?
`polars.LazyFrame.schema` issues a performance warning, advising to use `.collect_schema`

I think we should probably be doing the same? Else what's the point of us having both `LazyFrame.schema` and `LazyFrame.collect_schema`?

### Additional contract requirements

Accessing `schema` on a LazyFrame created through the current (non-V1) Narwhals API emits a performance warning whose message advises using `collect_schema()`. The warning category is not part of this requirement. This applies to LazyFrames across supported backends; the V1 API is outside this change.
