Incorrect authz policy order
Currently, some API requires the request contains either a valid session, or master key. This is represented as:
```go
policy.AnyOf(
	authz.PolicyFunc(policy.RequireMasterKey),
	policy.AllOf(
		authz.PolicyFunc(policy.DenyNoAccessKey),
		policy.RequireValidUser,
	),
)
```

However, due to ordering of the policies, if the session is expired, the produced error reason is `AccessKeyNotAccepted`, instead of the expected reason `NotAuthenticated`.  Client SDK would not refresh the session automatically and breaks the session.

To fix it, [HIDDEN] so that `NotAuthenticated` would be produced.

### Additional contract requirements

- When no user is present, the authorization error message must be exactly `authentication required`.
- When a session is expired, authorization must produce `NotAuthenticated` rather than `AccessKeyNotAccepted`.
