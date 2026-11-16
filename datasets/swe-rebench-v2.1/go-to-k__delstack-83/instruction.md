[Feature] Retry handling for other IAM operations
Throttling errors may occur with APIs such as GetRole that are not currently retried.

It could also be applied to ListAttachedRolePolicies.

```
ERR operation error IAM: GetRole, exceeded maximum number of attempts, 3, https response error StatusCode: 400, RequestID: 75592ee3-8859-435f-96b3-dc0c40e5153a, api error Throttling: Rate exceeded
```

### Additional contract requirements

Throttling errors from both the IAM GetRole operation and ListAttachedRolePolicies operation must be retried rather than returned immediately.
