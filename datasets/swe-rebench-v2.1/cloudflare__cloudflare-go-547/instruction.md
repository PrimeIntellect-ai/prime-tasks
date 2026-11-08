`PerformTraceroute` should work without an explicit colocation list
`PerformTraceroute` should work without an explicit colocation list passed to it.

## Expected behavior

When not passing/passing empty `colos` to `PerformTraceroute`, the 'colos' field should be omitted from the API request, causing all colos should be queried. [docs](https://api.cloudflare.com/#diagnostics-traceroute)

## Current behavior

When not passing/passing empty `colos` to `PerformTraceroute` an empty array is sent to the API, causing an error

```
failed to perform traceroute: error from makeRequest: HTTP status 400: content "{\n  \"result\": null,\n  \"success\": false,\n  \"errors\": [\n    {\n      \"code\": 1005,\n      \"message\": \"Colo is not a valid colo\"\n    }\n  ],\n  \"messages\": []\n}\n"
```

## Possible solution

https://github.com/cloudflare/cloudflare-go/blob/master/diagnostics.go#L14

[HIDDEN]

## Steps to reproduce (for bugs)

1. Have an enterprise plan
2. Execute `PerformTraceroute` with colos being an empty slice
   - for example with `go run -a github.com/jacobbednarz/cf-traceroute -api-key=${CF_TOKEN} -email=${CF_EMAIL} -targets=1.1.1.1 -account-id=${CF_ACC_ID}`

## Context

`github.com/jacobbednarz/cf-traceroute` requires an explicit colo list because of this behavior. If this is fixed, that parameter can be omitted.
Their code does not enforce the colo list but will error out as described above. With the adapted payload the API request should work just fine. (Verified via manual curl to the API)

## References

-

## Your Environment

Include as many relevant details about the environment you experienced
the bug in:

* Version used (e.g. git sha or specific tag): ` master`
* Environment name and version (e.g. Go 1.11, MacOS 10.14.1): ` go version go1.15.2 linux/amd64`

### Additional contract requirements

- When `colos` is omitted or empty, omit the `colos` field from the API request so the API queries all colos.
