Allow reading `Credentials` in `LoginClient` API
Currently there is only a method `onCredentialsChanged` that gives you new `Credentials?` object you base .

I have a case where I'd need read to access the `accessToken` and perform some action outside `LoginClient` with it. Currently there is no way to do so.

### Additional contract requirements

`LoginClient` exposes a `Future<Credentials?>` getter named `credentials`. Reading it returns the credentials currently available from the configured credentials storage, or `null` when no credentials are stored. This lets callers access the credentials (including their access token) without subscribing to credential-change notifications.
