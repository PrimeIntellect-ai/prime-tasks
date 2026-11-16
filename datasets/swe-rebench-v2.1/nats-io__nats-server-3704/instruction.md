Fix `/healthz` check for `js-enabled=true`
`js-enabled=true` is not a well defined health check request parameter currently.  It currently has the same effect that looking at the NATS Config to see if JS Should be enabled:

https://github.com/nats-io/nats-server/blob/d6f243f39bac2e0eaa577cd5e2bfa2d848a86389/server/monitor.go#L3012-L3021

We should instead just check the NATS Config to determine if JetStream should be enabled, and compare the current state to the config for the health check.

The `js-enabled=true` parameter should be changed to `js-enabled-only=true` and should terminate the Healthz endpoint after checking the Desired state (from the config) of JetStream against the Current state of JetStream

- `js-enabled-only=true` -> exit after checking if JetStream is enabled
- `js-server-only=true` -> exit after checking if Server is Current with Meta Leader
- no paramaters -> check everything

### Additional contract requirements

- The health check is served at the `/healthz` HTTP endpoint and accepts the query parameters `js-enabled-only` and `js-server-only`.
- When JetStream is enabled in the server configuration but is not running, a health check with `js-enabled-only=true` reports an `unavailable` status and the error returned by `NewJSNotEnabledError()`.
