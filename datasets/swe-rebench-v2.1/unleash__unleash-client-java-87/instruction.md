Improve error messages
When connecting to the unleash-server over http instead of https and the client only receives 301 it will only log 301 and not the new location header. This can make it hard for the use to understand why the client cannot connect to the server.

### Additional contract requirements

- `FeatureToggleResponse` in package `no.finn.unleash.repository` must expose a public method `getLocation()` that returns the value of the HTTP `Location` header when the server responded with a redirect, and `null` when the response carries no redirect `Location`.
- When a fetch is reported as unavailable because the server redirected (for example an HTTP 301), the error reported to the configured subscriber must include the redirect `Location` value in addition to the status code.
