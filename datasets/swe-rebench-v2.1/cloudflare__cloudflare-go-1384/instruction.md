Add GET for /dcv_delegation/uuid
### Current cloudflare-go version

0.76.0

### Description

https://api.cloudflare.com/client/v4/zones/<zone_id>/dcv_delegation/uuid is not currently supported by the Go SDK.

### Use cases

We need the ability to automate partial zone CNAME DCV delegation after zone creation in order to allow certificates to be auto-renewed.

### Potential cloudflare-go usage

```go
Simple Go SDK support for new endpoint.
```


### References

_No response_

### Additional contract requirements

- The SDK exposes the zone DCV delegation UUID endpoint as the public method `API.GetDCVDelegation(ctx context.Context, rc *ResourceContainer, params GetDCVDelegationParams) (DCVDelegation, ResultInfo, error)`, where `GetDCVDelegationParams` is an (currently empty) struct type that callers pass as the third argument.
- For a zone identified through `ZoneIdentifier`, the call issues a GET request to `/zones/<zone_id>/dcv_delegation/uuid`.
- The returned `DCVDelegation` value makes the UUID string returned by the endpoint available to the caller (via its `UUID` field).
