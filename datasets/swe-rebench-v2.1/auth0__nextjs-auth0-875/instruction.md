Redirects using withMiddlewareAuthRequired
### Checklist

- [X] The issue can be reproduced in the [sample app](https://github.com/auth0-samples/auth0-nextjs-samples/tree/main/Sample-01) (or N/A).
- [X] I have looked into the [README](https://github.com/auth0/nextjs-auth0#readme) and have not found a suitable solution or answer.
- [X] I have looked into the [examples](https://github.com/auth0/nextjs-auth0/blob/main/EXAMPLES.md) and have not found a suitable solution or answer.
- [X] I have looked into the [API documentation](https://auth0.github.io/nextjs-auth0/) and have not found a suitable solution or answer.
- [X] I have searched the [issues](https://github.com/auth0/nextjs-auth0/issues) and have not found a suitable solution or answer.
- [X] I have searched the [Auth0 Community](https://community.auth0.com/c/sdks/5) forums and have not found a suitable solution or answer.
- [X] I agree to the terms within the [Auth0 Code of Conduct](https://github.com/auth0/open-source-template/blob/master/CODE-OF-CONDUCT.md).

### Description

Making a redirect with `withMiddlewareAuthRequired`:

```tsx
export default withMiddlewareAuthRequired(async function middleware(
  req: NextRequest
) {
  return NextResponse.redirect("/register")
})
```

strips the status code and always returns a 200. That means that the document body results in `/register`.

This:
```tsx
export default async function middleware(
  req: NextRequest
) {
  return NextResponse.redirect("/register")
}
```

works fine...

### Reproduction

See description.

### SDK version

2.0.0

### Next.js version

12.3.1

### Node.js version

18.8
