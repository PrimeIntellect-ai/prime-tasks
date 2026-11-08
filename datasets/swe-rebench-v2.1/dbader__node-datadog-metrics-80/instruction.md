Make the datadog endpoint configurable
The endpoint URL of datadog should be configurable (for testing and special setups).
The underlying dogapi library already supports it.

### Additional contract requirements

- `BufferedMetricsLogger` accepts an `apiHost` option (also called the Datadog "site"). The logger exposes the resulting reporter as its `reporter` property, and that reporter exposes the configured host as an `apiHost` property.
- `DataDogReporter` is exported from `lib/reporters.js` and is constructed as `DataDogReporter(apiKey, appKey, apiHost)`. It exposes the configured host as an `apiHost` property.
- A leading `app.` is stripped from the host, so `app.datadoghq.eu` is exposed as `datadoghq.eu`.
- The configured host determines the Datadog endpoint that metrics are submitted to: with host `datadoghq.eu`, metric submissions are sent to `api.datadoghq.eu`.
