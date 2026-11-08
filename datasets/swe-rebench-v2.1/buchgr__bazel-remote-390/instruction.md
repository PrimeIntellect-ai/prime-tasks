Configure http request duration buckets for lower latency caches
Some smaller bucket sizes should be added here to cover lower latency caches: https://github.com/buchgr/bazel-remote/blob/b42d315f3763f9d365c6fd4119e22e66ea252d20/main.go#L50

Here's some numbers from a cache deployment with 4 replicas of bazel-remote (all replicas restarted in the last 24h):

Taking a look at the bucket counters themselves:
```
sum(http_request_duration_seconds_bucket{service="bazel-remote", endpoint!="metrics"}) by (le)
```

```
{le="0.5"}	30528468 # 30528468
{le="1"}	30541059 # 12591
{le="2.5"}	30543574 # 2515
{le="5"}	30543596 # 22
{le="10"}	30543605 # 9
{le="20"}	30543605
{le="40"}	30543605
{le="80"}	30543605
{le="160"}	30543605
{le="320"}	30543605
{le="+Inf"}	30543605
```

Which shows that around 99.9% of request durations are 0.5 or lower (histogram buckets are cumulative counts).

Calculating the mean request duration:

```
sum(http_request_duration_seconds_sum{service="bazel-remote", endpoint!="metrics"})
  /
sum(http_request_duration_seconds_count{service="bazel-remote", endpoint!="metrics"})
```

Returns 0.00845, which is a couple of orders of magnitude lower than the lowest bucket duration.

---

We can do one of:

1. Add some extra smaller buckets at the lower end (increases the cardinality again)
2. Keep the number of buckets the same, but reduce the smallest few
3. Make the duration configurable

Making durations configurable is possibly the best option, since altering bucket sizes makes querying old data less useful.

fwiw the default prometheus go client range looks like it would be better for my deployment at least: https://github.com/prometheus/client_golang/blob/b7799362e0ac323f658fb8d52c2d6df001cf272c/prometheus/histogram.go#L63

### Additional contract requirements

- The configuration supports an optional `endpoint_metrics_duration_buckets` key, a list of numbers. The corresponding field on the `Config` type in package `config` is `MetricsDurationBuckets []float64`.
- When `endpoint_metrics_duration_buckets` is omitted, the buckets default to `[.5, 1, 2.5, 5, 10, 20, 40, 80, 160, 320]`.
- The configured buckets are used as the histogram buckets for the request-duration metrics exposed by the metrics endpoint.
- A configuration that specifies duplicate values for `endpoint_metrics_duration_buckets` is rejected with an error whose message contains the text `endpoint_metrics_duration_buckets`.


- If `endpoint_metrics_duration_buckets` contains duplicate values, reject the configuration with an error message containing the exact text `'endpoint_metrics_duration_buckets'`.
