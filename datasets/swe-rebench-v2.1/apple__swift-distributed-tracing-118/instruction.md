Use nanosecondsSinceEpoch in `SpanEvent`
In #114 we added `nanosecondsSinceEpoch` to the `TracerInstant`. `SpanEvent`, however, still uses `millisecondsSinceEpoch`.
We should also base `SpanEvent` on nanoseconds, exposing the same convenience `millisecondsSinceEpoch` accessor we do with `TracerInstant`.
