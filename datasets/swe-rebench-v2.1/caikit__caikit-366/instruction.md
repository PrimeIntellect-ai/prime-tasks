HTTP Server Shutdown with Local Model Dirs Sync
## Describe the bug

When running `caikit.runtime.http_server` with `runtime.lazy_load_local_models: true`, the server fails to terminate on ctrl-C due to the polling timer.

### Additional contract requirements

- The HTTP server must expose `HEALTH_ENDPOINT` in `caikit.runtime.http_server` with the value `"/health"` and respond successfully to GET requests at that path.
