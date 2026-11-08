withMiddlewareAuthRequired returnTo param should not be full URL
### Checklist

- [X] The issue can be reproduced in the [sample app](https://github.com/auth0-samples/auth0-nextjs-samples/tree/main/Sample-01) (or N/A).
- [X] I have looked into the [README](https://github.com/auth0/nextjs-auth0#readme) and have not found a suitable solution or answer.
- [X] I have looked into the [examples](https://github.com/auth0/nextjs-auth0/blob/main/EXAMPLES.md) and have not found a suitable solution or answer.
- [X] I have looked into the [API documentation](https://auth0.github.io/nextjs-auth0/) and have not found a suitable solution or answer.
- [X] I have searched the [issues](https://github.com/auth0/nextjs-auth0/issues) and have not found a suitable solution or answer.
- [X] I have searched the [Auth0 Community](https://community.auth0.com/c/sdks/5) forums and have not found a suitable solution or answer.
- [X] I agree to the terms within the [Auth0 Code of Conduct](https://github.com/auth0/open-source-template/blob/master/CODE-OF-CONDUCT.md).

### Description

I have implemented `withMiddlewareAuthRequired` to protect our pages. The `returnTo` param that is added automatically as redirect when navigating to a protected page directly contains the full URL instead of a relative path to the page.

I expect a relative URL to be set as described in the docs:
"`/api/auth/login`: Your Next.js application redirects users to your identity provider for them to log in (you can optionally pass a returnTo parameter to return to a custom relative URL after login, for example /api/auth/login?returnTo=/profile)."

We host our app as a container and in that environment it still shows localhost as the domain instead of our custom domain. (ex. "/api/auth/login?returnTo=http://localhost:3000/profile")

Also, these [docs](https://auth0.github.io/nextjs-auth0/modules/helpers_with_middleware_auth_required.html) could use some updates. This import does not work:
`import { withMiddlewareAuthRequired } from '@auth0/nextjs-auth0/middleware';`
But this does:
`import { withMiddlewareAuthRequired } from '@auth0/nextjs-auth0/edge';`

### Reproduction

1. Sample repo: https://github.com/auth0-samples/auth0-nextjs-samples/compare/main...zcarlson-gmgt:auth0-nextjs-samples:main
2. Implement middleware authentication using the following:
`import { withMiddlewareAuthRequired } from '@auth0/nextjs-auth0/edge';
export default withMiddlewareAuthRequired();`

1. Navigate to a page that should be protected (ex. localhost:3000/profile)
1. See that the `returnTo` param is set to localhost:3000/profile instead of /profile


### SDK version

2.1.0

### Next.js version

13.1

### Node.js version

18.12.0
