Support returnTo in withMiddlewareAuthRequiredFactory
### Checklist

- [X] I have looked into the [Readme](https://github.com/auth0/nextjs-auth0#readme), [Examples](https://github.com/auth0/nextjs-auth0/blob/main/EXAMPLES.md), and [FAQ](https://github.com/auth0/nextjs-auth0/blob/main/FAQ.md) and have not found a suitable solution or answer.
- [X] I have looked into the [API documentation](https://auth0.github.io/nextjs-auth0/) and have not found a suitable solution or answer.
- [X] I have searched the [issues](https://github.com/auth0/nextjs-auth0/issues) and have not found a suitable solution or answer.
- [X] I have searched the [Auth0 Community](https://community.auth0.com) forums and have not found a suitable solution or answer.
- [X] I agree to the terms within the [Auth0 Code of Conduct](https://github.com/auth0/open-source-template/blob/master/CODE-OF-CONDUCT.md).

### Describe the problem you'd like to have solved

On successful auth using `withMiddlewareAuthRequiredFactory`, I want to `returnTo` my own specified URL, but cannot because `withMiddlewareAuthRequiredFactory` [hard-codes](https://github.com/auth0/nextjs-auth0/blob/dc893143d23b8797bcfbb0317fec0bccaf029083/src/helpers/with-middleware-auth-required.ts#L79) a value.

### Describe the ideal solution

Support an input into the middleware constructor OR (better) the middleware fn itself to accept a returnTo param, as with similar APIs in this SDK.

### Alternatives and current workarounds

I have to redirect or nav my user from within my application, which is undesirable because it adds a highly undesirable entry into my user's navigation history/stack.

### Additional context

This is for the next@beta, at the time of writing!

### Additional contract requirements

- `withMiddlewareAuthRequired` accepts either a plain middleware function or an options object.
- The options object supports:
  - `middleware`: a custom middleware function to run after the authentication check.
  - `returnTo`: a string, or a function `(req: NextRequest) => Promise<string> | string`, whose result is used as the `returnTo` query parameter of the login redirect.
- When both `returnTo` and `middleware` are supplied, both are honored: the `returnTo` value is used for the login redirect of unauthenticated requests, and the custom middleware runs for authenticated requests.
