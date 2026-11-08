Add BucketOptions for DistributionValue
This is as per Metrics.proto: https://github.com/census-instrumentation/opencensus-proto/blob/master/src/opencensus/proto/metrics/v1/metrics.proto#L209

Counterpart in Java: https://github.com/census-instrumentation/opencensus-java/pull/1484

Implement here : https://github.com/census-instrumentation/opencensus-python/blob/master/opencensus/metrics/export/value.py#L182

### Additional contract requirements

- In module `opencensus.metrics.export.value`, add a public class `BucketOptions`
  whose constructor is `BucketOptions(type_=None)`. `type_` is an optional
  bucket-type object (for example an `Explicit`); passing `None` means the
  distribution has no histogram. `BucketOptions` exposes a `type_` property
  returning the stored bucket type.
- In module `opencensus.metrics.export.value`, add a public class `Explicit`
  whose constructor is `Explicit(bounds)`. `bounds` is a non-empty list of
  strictly increasing positive numbers. The constructor raises `ValueError` if
  `bounds` is `None`, empty, not strictly increasing, or contains a
  non-positive value. `Explicit` exposes a `bounds` property that returns a
  copy of the bounds, so mutating the returned list does not change the
  object's bounds.
- `ValueDistribution.__init__` has the signature
  `ValueDistribution(count, sum_, sum_of_squared_deviation, bucket_options,
  buckets=None)`. `bucket_options` must not be `None`. When
  `bucket_options.type_` is not `None`, `buckets` must contain exactly
  `len(bucket_options.type_.bounds) + 1` buckets; otherwise `buckets` must be
  `None`. Invalid combinations raise `ValueError`.
- `ValueDistribution.bucket_options` is a property returning the
  `BucketOptions` instance associated with the distribution, or `None` if there
  is no histogram.
