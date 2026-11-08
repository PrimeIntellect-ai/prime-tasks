Allow the agent User-Agent header to be configurable
I would like to be able to control the User-Agent header of the agent when communicating with the management server. Currently this defaults to `Go-http-client/1.1`. It can be useful to identify traffic for logging.

I would propose adding a [HIDDEN] to `StartSettings` and setting the User-Agent header [HIDDEN].

### Additional contract requirements

- `types.StartSettings` must provide a `Header http.Header` field. Send the supplied headers on HTTP requests and WebSocket connection requests.
- Callers must be able to configure the User-Agent header sent when the agent communicates with the management server.
