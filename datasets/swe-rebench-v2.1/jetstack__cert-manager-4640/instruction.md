clock_time_seconds metric should be a gauge

**Describe the bug**:
As other people reported (https://github.com/jetstack/cert-manager/pull/4105#issuecomment-930563632) the cert-manager clock_time_seconds metric should be a gauge, not a counter for it to work properly.

This is also a general view that timestamps should be gauges: https://www.robustperception.io/are-increasing-timestamps-counters-or-gauges

Taking into account that the other timestamps metrics offered by cert-manager are gauges, this makes even more sense to change to a gauge as well.

Open to discussion and also to contribute to a fix.

### Additional contract requirements

- The clock time must be exposed as a gauge metric named `clock_time_seconds_gauge` in the `certmanager` namespace, i.e. the fully qualified Prometheus metric name is `certmanager_clock_time_seconds_gauge`. Its value is the current clock time in seconds since 1970/01/01 UTC.
- The pre-existing `certmanager_clock_time_seconds` metric must remain exposed as a counter for backwards compatibility.
