Support for 'client_secret_post'
Hello! First of all, thanks for your hard word on this project :)

While working with this library to replace an existing OIDC auth client, I noticed that there is currently only support for `client_secret_basic` authentication method. This is a blocker for my team, because we are only allowed to enable `client_secret_post`.

I went ahead and opened PR #84 which contains the changes need to support `client_secret_post` for both the `client_credentials` and `password` grant types.

### Additional contract requirements

- `OAuth2Client` must expose an `authenticationMethod` option that supports `client_secret_basic` and `client_secret_post`. Selecting `client_secret_post` configures token requests to use that authentication method.
