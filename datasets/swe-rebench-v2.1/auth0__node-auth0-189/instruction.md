Grant type `/oauth/ro` deprecated
Hi, can you change **grant_type: "/oauth/ro"** to **grant_type:"password"**

### Additional contract requirements

Add a public instance method `passwordGrant(userData, cb)` on the `OAuthAuthenticator` class exported by `src/auth/OAuthAuthenticator.js`.

- `userData` is an object containing the user's `username` and `password`.
- When `userData` is missing, throw an `ArgumentError` with the message `Missing user data object`.
- When the `username` field is absent, throw an `ArgumentError` with the message `username field is required`.
- When the `password` field is absent, throw an `ArgumentError` with the message `password field is required`.
- The request is sent as a POST to `/oauth/token`.
- The request body includes the user data and the authenticator's `clientId` as `client_id`.
- The default `grant_type` is `password`.
- When `userData.realm` is provided, `grant_type` is `http://auth0.com/oauth/grant-type/password-realm`.
- When `cb` is provided, the result is delivered through the callback as `(err, result)`; otherwise a Promise that resolves with the token response is returned.
