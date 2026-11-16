Allow skipping TLS verification for upstreams in interceptor
### Proposal

In-cluster upstreams using TLS are often using self signed certificates or certificates that are not trusted by the interceptor. Adding all certificates to the trusted certificates for the interceptor might not always be possible.

### Use-Case

_No response_

### Is this a feature you are interested in implementing yourself?

Yes

### Anything else?

_No response_

### Additional contract requirements

- The interceptor must provide a way to skip TLS certificate verification when it connects to upstreams.
- `runProxyServer` takes its TLS settings as a `map[string]interface{}`. The existing string entries `certificatePath`, `keyPath` and `certstorePaths` keep their meaning.
- Setting the boolean entry `skipVerify` to `true` makes the interceptor skip verification of upstream server certificates. When the entry is absent or `false`, upstream certificates are verified as before.
