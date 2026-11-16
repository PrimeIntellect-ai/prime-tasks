Update the timeout for default failure to avoid false positives
Ratify should default failure.
https://github.com/deislabs/ratify/blob/efe40f7e9bed136f03f21885443b9f82aa27e3b0/pkg/executor/core/executor.go#L36
Currently the timeout is 8 seconds and so gatekeeper will fail and let the deployment through.

1. Update timeout to a shorter interval to fail the deployment.
2. Ensure that the signature is still requested so that the next deployment can succeed with a cached request.

### Additional contract requirements

- When verification times out, the server must respond with HTTP 500 Internal Server Error so the deployment is blocked.
