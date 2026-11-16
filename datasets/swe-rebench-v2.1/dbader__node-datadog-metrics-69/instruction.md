Add median for histogram metrics
When using DogStatsD, the histogram type calculates a `<metric_name>.median` metric that this package does not. It would be great to add that here.

(Context: I’m experimenting with transitioning an app from DogStatsD to this for an environment where the other system/host metrics DogStatsD collects aren’t needed, so we can reduce configuration overhead and cost.)

I’d be happy to submit a PR to add this, if helpful.

### Additional contract requirements

- In the default histogram output series, emit `<metric_name>.median` at index 5, before the percentile metrics (`<metric_name>.75percentile`, `<metric_name>.85percentile`, `<metric_name>.95percentile`, and `<metric_name>.99percentile`) at indices 6 through 9.
- The median is the middle sample after sorting the histogram samples in ascending numeric order. For an even number of samples, it is the arithmetic mean of the two middle samples.
- For an empty histogram, the median value is zero.
