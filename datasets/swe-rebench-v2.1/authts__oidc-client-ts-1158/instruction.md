OIDC Client; can refresh token externally as RefreshState is not exportered
I am using the OIDC client instead of the user manager as need to do some low level stuff with service workers.

But the `useRefreshToken` method of the needs an instance of  RefreshState; which is not exported

### Additional contract requirements

- The package's public entry point must export the `RefreshState` type, so that a consumer importing the package can name it and pass a value of that type as the `state` argument of `OidcClient.useRefreshToken`.
