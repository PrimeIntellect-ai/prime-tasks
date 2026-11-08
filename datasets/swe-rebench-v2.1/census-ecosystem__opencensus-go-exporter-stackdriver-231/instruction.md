Support multiple monitored resource types in one process
**NB:** Before opening a feature request against this repo, consider whether the feature should/could be implemented in exporter libraries in other languages. If so, please [open an issue on opencensus-specs](https://github.com/census-instrumentation/opencensus-specs/issues/new) first.

**Is your feature request related to a problem? Please describe.**
We are using `GetMonitoredResource` in our code to determine which monitoring resource type to use. The resource type is determined by the metric name currently. If the metric is a built-in metric, we send it with a non-`global` resource type. If not, we send it with `global` resource type as custom metrics.

Now `GetMonitoredResource` was removed in v0.12.7.

**Describe the solution you'd like**
Provide some option similar to `GetMonitoredResource`.

### Additional contract requirements

Add a public field `ResourceByDescriptor` to the exporter `Options` in package `contrib.go.opencensus.io/exporter/stackdriver`, with type `func(*metricdata.Descriptor, map[string]string) (map[string]string, monitoredresource.Interface)`, where `metricdata` is `go.opencensus.io/metric/metricdata` and `monitoredresource` is `contrib.go.opencensus.io/exporter/stackdriver/monitoredresource`.

When this field is set, the exporter derives the monitored resource for each time series from the metric descriptor and the time series label map. The monitored resource returned for a time series is attached to that time series, and the label map returned for it is used as the metric labels of that time series. If the returned monitored resource type is empty, the time series uses the `global` resource type with no resource labels.
