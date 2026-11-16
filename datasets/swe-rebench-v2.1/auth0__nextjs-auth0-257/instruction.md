getAccessToken clears custom session.user attributes set via onUserLoaded
### Description

As per the README, onUserLoaded can be used to set custom session.user attributes (eg `session.user.age`). However these attributes are removed when the accessToken is refreshed.

[HIDDEN]

This appears unintentional, as later on it attempts to preserve the `session.user` ([HIDDEN]

### Reproduction

1. Create a callback onUserLoaded that sets a custom `session.user` attribute (such as the example in the README that sets `session.user.age`

```
await auth0.handleCallback(req, res, {
      onUserLoaded: async (req, res, session, state) => {
        return {
          ...session,
          user: {
            ...session.user,
            age: 20
          }
        };
      }
    });
```


2. Force a token refresh

```
  const tokenCache = auth0.tokenCache(request, response);
  await tokenCache.getAccessToken({
    refresh: true,
  });
```

3. Observe the users session

```
const session = await auth0.getSession(req);
console.log(session);
```

The custom attribute will have been removed

### Environment

Version `0.16.0`

### Additional contract requirements

- Preserve custom attributes added to `session.user` (for example, `session.user.age`) when refreshing an access token.
- Also preserve the root-level custom session property `foo` when applying a refreshed access token.
