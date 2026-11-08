Readiness endpoint
## Specific Demand

Does dufs provide a readiness endpoint or URL that could be used in the context of Kubernetes? (or similar).

My local setup enforces authentication, and therefore the `/` URL returns a 401 status code, which leads Kubernetes into thinking the application is not ready.

## Implement Suggestion

It is common practice for applications to provide either a separate port for readiness checks, or a dumb URL like `/_ready` or `/_healthz/ready` that simply returns `OK` text with a 200 HTTP status.

Thank you for developing and maintaining `dufs`: it is an amazing tool, simple and to the point. This clearly sets it apart of other bloated alternatives.

### Additional contract requirements

- The readiness endpoint is served at the path `__dufs__/health`, relative to any configured path prefix (for example, with `--path-prefix xyz` it is reached at `xyz/__dufs__/health`).
- A successful readiness request returns HTTP status 200 with the response body `{"status":"OK"}`.
- The readiness endpoint responds successfully without authentication, even when the root URL is protected by authentication.
