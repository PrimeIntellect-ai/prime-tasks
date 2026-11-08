Support method to simplify token refresh
## 🚀 Feature Proposal

`simple-oauth2` supports a way to easily refresh access tokens by using the `refresh_token` (which you get if you request the `offline` scope:

```javascript
const AccessToken = require('simple-oauth2/lib/access-token')

[HIDDEN]

const token = {} // ... get token somehow
await refresh(token)
```

It would be cool to expose some shortcut in the fastify plugin to do this, given a OAuth2 token object

## Motivation

We already have a nice `this.getAccessTokenFromAuthorizationCodeFlow(request)` helper function. It would be nice to have something similar for renewing tokens as well.

What do you think?

I am happy to provide an implementation, if this idea makes sense for everyone.

## Example

(see above)

### Additional contract requirements

- Add a method `getNewAccessTokenUsingRefreshToken(refreshToken, params, callback)` on the Fastify instance. It exchanges an OAuth2 refresh token for a new access token.
- `refreshToken` is the OAuth2 refresh token string.
- `params` is optional. When provided, its entries are sent as additional parameters of the token refresh request (for example an extra `scope`).
- `callback` is optional. When it is omitted the method returns a Promise; when it is provided it is called as `callback(err, result)`.
- The result (the Promise resolution value, or the callback's second argument) is the OAuth2 token response. It contains `access_token` (string), `refresh_token` (string), `token_type` (string) and `expires_in` (integer number of seconds). The token response is exposed either directly as the result or under a `token` property of the result.
- On failure the Promise is rejected, or the callback is called with an error as its first argument.
