module/apmotel: consider defaulting to delta temporality for metrics
Aggregating metrics in Elasticsearch tends to be easier when recorded as deltas. This might change if/when we migrate to TSDS, so this needs some investigation and discussion, but I think it may be a better default for now.

### Additional contract requirements

By default, the apmotel gatherer must use delta temporality for synchronous counters, observable counters, and histograms. Metrics from these instruments collected again later must represent the measurements since the preceding collection, rather than cumulative totals.
