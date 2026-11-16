importUsers as first API command doesn't authenticate
To recreate:

* Create an API connection in the standard way with `create:users` permission
* Call `auth0.jobs.importUsers`

The call will fail with a 401, as importUsers does not request an auth token prior to running its own query. If you call another API method first (such as `createUser` or `findByEmail`) it works fine.

I think this is because this method (and possibly `UsersManager.impersonate`) roll their own POST request, rather than going through Auth0RestClient as every other method does.

### Additional contract requirements

- The `JobsManager` constructor accepts a `tokenProvider` option: an object exposing `getAccessToken(): Promise<string>`. When `importUsers` is called, it must obtain an access token from that provider and send it as an `Authorization: Bearer <token>` header on the request, even when `importUsers` is the first API call made.
- For an HTTP 500 response from `importUsers` at `https://tenant.auth0.com/jobs/users-imports`, the rejected promise's error message must be exactly `cannot POST https://tenant.auth0.com/jobs/users-imports (500)`.
- When `importUsers` encounters a request-level error whose message is `printer on fire`, the rejected promise's error message must be exactly `printer on fire`.
