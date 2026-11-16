Protect API routes with withMiddlewareAuthRequired
### Checklist

- [X] I have looked into the [README](https://github.com/auth0/nextjs-auth0#readme) and have not found a suitable solution or answer.
- [X] I have looked into the [examples](https://github.com/auth0/nextjs-auth0/blob/main/EXAMPLES.md) and have not found a suitable solution or answer.
- [X] I have looked into the [API documentation](https://auth0.github.io/nextjs-auth0/) and have not found a suitable solution or answer.
- [X] I have searched the [issues](https://github.com/auth0/nextjs-auth0/issues) and have not found a suitable solution or answer.
- [X] I have searched the [Auth0 Community](https://community.auth0.com/c/sdks/5) forums and have not found a suitable solution or answer.
- [X] I agree to the terms within the [Auth0 Code of Conduct](https://github.com/auth0/open-source-template/blob/master/CODE-OF-CONDUCT.md).

### Describe the problem you'd like to have solved

I have a NextJS server that has both page routes and API endpoints under `/api`. I want to use `withMiddlewareAuthRequired` to validate session token for all page routes and API endpoints that are not ignored by `config.matcher`. Once `@auth0/nextjs-auth0` did its magic, I want to execute custom code to check for the presence of specific roles and custom claims in the token. If these elements are not present, depending on the entry point (page route or API endpoint) I'd either redirect the user to Auth0 login or return a 401.

I can already craft my custom logic for the middleware by providing `withMiddlewareAuthRequired` a function. However right now when using `withMiddlewareAuthRequired` if I attempt to access a protected API route without any authentication information, the client gets redirected to the Auth0 login.

### Describe the ideal solution

IMO redirection is the desired behaviour when accessing page routes however when you access any protected endpoint under `/api` it should return a 401 without redirecting the client.

### Alternatives and current workarounds

I don't have any since the way the redirect is handled is outside of the user control. One way would be to ignore all API routes but it defeats the purpose of middleware IMO. I'd have to craft the token validation myself and apply it manually to all protected API endpoints which is error prone.

### Additional context

next@12.3.2
@auth0/nextjs-auth0@2.0.0-beta.1
node@16.15.1

### Additional contract requirements

- For unauthenticated requests to protected API endpoints, respond with a 401 rather than redirecting to login.
- If `routes.unauthorized` is configured, use that route as the unauthorized destination for protected API requests. If it is not configured, the default unauthorized route is `/api/auth/401`.
