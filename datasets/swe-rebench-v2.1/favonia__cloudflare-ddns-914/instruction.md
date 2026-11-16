Add hints for common cloudflare errors
Since 1.14.0, we no longer do remote token verification, and sadly there are no official documentation on the error codes returned by Cloudflare, but we can still "guess" the fixes based on the server's current behavior. For example:

1. 10000 probably means the API token is invalid or insufficient permissions are given.
2. (more to add to this issue)

### Additional contract requirements

When a Cloudflare API call fails because of an authentication or authorization error (for example, an invalid API token or insufficient permissions), a user-visible hint must be emitted.

For DNS record and zone operations, the hint message must be exactly `Double check your API token. Make sure you granted the "Edit" permission of "Zone - DNS"`.

For WAF list operations, the hint must use the hint identifier `pp.HintWAFListPermission` and its message must be exactly `Double check your API token and account ID. Make sure you granted the "Edit" permission of "Account - Account Filter Lists"`.


- For a failed DNS-record listing, report the failure using the notice format `Failed to retrieve %s records of %q: %v`.
