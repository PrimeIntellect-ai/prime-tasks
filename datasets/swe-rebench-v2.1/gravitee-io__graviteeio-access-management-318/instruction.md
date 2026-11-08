[oidc] UserInfo Endpoint access with POST and bearer body
Currently we only accept UserInfo Request with an Access Token sent using the Authorization header field.

We should handle UserInfo Endpoint access with POST and bearer body

### Additional contract requirements

- The UserInfo endpoint must accept a POST request that carries the bearer access token in the request body.
- In that POST body the access token is supplied as the `access_token` parameter, using the `application/x-www-form-urlencoded` representation.
- Requests that present the bearer access token in the `Authorization` header keep working as before.
