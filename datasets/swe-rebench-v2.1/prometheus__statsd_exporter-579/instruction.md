panic in dogstatsd extended aggregation parsing
https://github.com/prometheus/statsd_exporter/pull/558#pullrequestreview-2259676259 – breaking this out into an issue by itself.

From @m-barthelemy:

> After updating to 0.27.1, [this line](https://github.com/prometheus/statsd_exporter/pull/558/files#diff-a9794bf96da36f26e5b9f52911da6346f9d53f8039ed1adf2e804b6782b04febR235) is triggering a panic: runtime error: index out of range [1] with length 1 for us.

Could you run the exporter with `--log.level=debug` and give us an example of a line that's triggering this? Ideally, add it as a test case and see if that also fails.

@GrgDev [HIDDEN], do you have capacity to look into that?

### Additional contract requirements

- Malformed input in the DogStatsD extended-aggregation parsing path must not cause a panic when splitting the input yields too few parts.
