My gauge are always global and not K8S or GCE
This is my stackdriver config

```
	opt := stackdriver.Options{
		// MetricPrefix helps uniquely identify your metrics.
		//	ProjectID:    project,
		MetricPrefix: "backup",
		OnError: func(err error) {
			log.Printf("Failed to send metrics on stackdriver: %v", err.Error())
		},
		Context: cont,
		Timeout: 5 * time.Second,
		//MonitoredResource: monitoredresource.Autodetect(),
		ReportingInterval: 1 * time.Minute,
		ResourceDetector:  auto.Detect,
	}
```
When i run my app on GKE, all my gauge have resource type Global but not K8S_container

On debug i can't see everything to set them on this method: https://github.com/census-instrumentation/opencensus-go/blob/5ae9166f90ff989c557e45fcb9592ac59afa0fa0/metric/metricexport/reader.go#L183

### Additional contract requirements

- For each exported metric, use its supplied resource when present. Otherwise, use the exporter’s configured `Options.Resource` monitored resource when available; use the global resource only when neither source provides a resource. A resource supplied to the metric, including one obtained through resource detection, takes precedence over `Options.Resource`.
