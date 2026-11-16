[oidc] Request with prompt=none when not logged in
As part of OpenID Connect certification :

`Request with prompt=none when not logged in`

`1.401 | fault | Expected error, didn't get it`

### Additional contract requirements

- For a request with `redirect_uri=http://localhost:9999/callback`, the response `Location` must be exactly `http://localhost:9999/callback?error=login_required`.
