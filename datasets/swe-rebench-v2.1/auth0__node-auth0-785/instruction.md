[ManagementClient] Delete All User Authenticators
### Describe the problem you'd like to have solved

The [Delete All Authenticators](https://auth0.com/docs/api/management/v2#!/Users/delete_authenticators) endpoint doesn't seem to be available in the `ManagementClient`

### Describe the ideal solution

Make it possible to use the `ManagementClient` to delete all user's authenticators.

```ts
client.deleteAllUserAuthenticators({ id })
```

### Alternatives and current work-arounds

I currently do this using Axios, and it's preventing me from migrating to this library.

### Additional contract requirements

- The public method is `UsersManager.deleteAllAuthenticators(params, cb)`; it sends a `DELETE` request to `/api/v2/users/{id}/authenticators`.
- `params` must contain a non-null string `id`. A missing, `null`, or non-string `id` causes a synchronous `ArgumentError`.
- When `cb` is supplied it is invoked as `cb(err)`; when it is omitted the method returns a Promise that resolves on success and rejects with the request error.
