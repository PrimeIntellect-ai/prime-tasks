Add support for checking plugin config health
Given a Grafana app/datasource plugin before saving it it will call a test function provided by the client side app/datasource. It would be nice if you could call the backend plugin to verify the health of a configured app/datasource instance.

Later we could possibly show iindication n UI whether certain app/datasource is online/working or not.

### Additional contract requirements

The backend health check must receive the configuration belonging to the app or datasource instance being checked. The caller must be able to determine the health outcome returned by the backend check.

Concretely:

- The protobuf `CheckHealth.Request` message carries the instance configuration in its `Config` field (a `PluginConfig`).
- The Go handler interface `CheckHealthHandler` has the method `CheckHealth(ctx context.Context, req *CheckHealthRequest) (*CheckHealthResult, error)`.
- `CheckHealthRequest` has a `PluginConfig` field of the existing `PluginConfig` type, populated from the `Config` of the incoming health check request, including its org ID, plugin ID, plugin type, JSON data, decrypted secure JSON data and datasource configuration.
- The `Status` of the `CheckHealthResult` returned by the handler is reported back to the caller as the health status of the response, and any error returned by the handler is returned to the caller.
