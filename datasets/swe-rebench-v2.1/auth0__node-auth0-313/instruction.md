Add a method for the refresh_token grant type
There is an obsolete method for delegation flows that used to (kind of) support the refresh_token grant type.

At this point, there's no API method for refreshing a token.

Please add one!

### Additional contract requirements

- Add `OAuthAuthenticator.refreshToken(userData, cb)` for the `refresh_token` grant and expose it as `AuthenticationClient.refreshToken(userData, cb)`.
