Crash at event_handler.ex:63 if tag value is missing - intentional?
I have a question regarding `TelemetryMetricsStatsd` and its `EventHandler`. In our environments we very subtly lose all of our metrics due to a crash which we suspect is caused by `Map.fetch!/2` as a tag value is missing.

Is it intentional to crash here if the value does not exist for a given tag? If that is the case, is this documented?

Our metrics.ex is currently very long and messy due to how tricky it is to manage the tags for different kinds of metrics, and I was hoping that it would be fine to configure the metrics such that if a value for the key exists, just use that, so that we can reuse a lot of functions. This means that more of the tag handling is common for all metrics, and the exceptions are handled more cleanly.

Currently this behaviour is not the same as the `ConsoleReporter` that I tend to use when I develop as we do not want to report any metrics to anywhere during development, but if it looks this way I either need to do that or to implement some kind of tests that copy this behaviour such that we catch the crash before deployment. Currently this process dies upon deployment and then we're blind.

This is from the tag 0.4.0 I think, but the line still exists in latest.

https://github.com/beam-telemetry/telemetry_metrics_statsd/blob/cda8cca8b204c8c870b2da691817bab7bd6dc4f1/lib/telemetry_metrics_statsd/event_handler.ex#L63

### Additional contract requirements

A telemetry event that omits a configured tag value must not crash the reporter. When another configured tag has a value in the event, the emitted metric must retain that value.
