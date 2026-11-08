Dont set backendRequestTimeout to Request Timeout when Retries are set
*Description*:
>What issue is being seen? Describe what should be happening instead of
the bug, for example: The expected value isn't returned, etc.

https://github.com/envoyproxy/gateway/blob/1376cae998ad5cea54bae765914908ee08a6121e/internal/gatewayapi/route.go#L328 should only be set when Retries are unset
https://github.com/envoyproxy/gateway/blob/1376cae998ad5cea54bae765914908ee08a6121e/internal/gatewayapi/route.go#L358

*Repro steps*:
> Include sample requests, environment, etc. All data and inputs
required to reproduce the bug.

>**Note**: If there are privacy concerns, sanitize the data prior to
sharing.

*Environment*:
>Include the environment like gateway version, envoy version and so on.

*Logs*:
>Include the access logs and the Envoy logs.
