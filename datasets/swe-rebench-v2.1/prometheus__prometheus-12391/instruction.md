Add feature flag to control /api/v1/metadata
## Proposal

The current `/api/v1/metadata` includes every instance of the metric definition. There are [cases where application bugs introduce high cardinality HELP text](https://github.com/prometheus/jmx_exporter/issues/703).

It would be useful to have a flag to squash this and only return one (fist?) instance of the definitions in order to avoid expensive (many megabytes) of metadata being returned by this API endpoint.

### Additional contract requirements

The `/api/v1/metadata` endpoint accepts the `limit_per_metric` query parameter. A value of `1` limits the response to at most one metadata definition for each metric. This control can be used together with the existing total `limit` parameter; the total limit must still be respected.
