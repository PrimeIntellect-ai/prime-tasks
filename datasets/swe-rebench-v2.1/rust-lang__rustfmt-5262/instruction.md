wrap_comments can break up type links
Similar to #5250, I have a problem when addressing types. They get split over multiple lines and are not valid links anymore in rust doc.

```
/// [IntermediateBucketResult](crate::aggregation::intermediate_agg_result::IntermediateBucketResult)
```

This is converted to:
```
/// [IntermediateBucketResult](crate::aggregation::intermediate_agg_result::
/// IntermediateBucketResult)
```
