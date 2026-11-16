withPageAuthRequired not redirecting to the correct url if there are multiple url params
<!--
**Please do not report security vulnerabilities here**. The Responsible Disclosure Program (https://auth0.com/whitehat) details the procedure for disclosing security issues.

Thank you in advance for helping us to improve this library! Please read through the template below and answer all relevant questions. Your additional work here is greatly appreciated and will help us respond as quickly as possible. For general support or usage questions, use the Auth0 Community (https://community.auth0.com/) or Auth0 Support (https://support.auth0.com/). Finally, to avoid duplicates, please search existing Issues before submitting one here.

By submitting an Issue to this repository, you agree to the terms within the Auth0 Code of Conduct (https://github.com/auth0/open-source-template/blob/main/CODE-OF-CONDUCT.md).
-->

### Describe the problem
I have an SSR page that is protected by `withPageAuthRequired`. The url for this page is in the format of `http://localhost:3000/events?city=some-city&start=xxxx-xx-xx&end=xxxx-xx-xx`.

When I'm logged in I have no problem accessing this page. When I'm not logged in I am redirected to the login page as expected. The problem is after logging in, I am redirected to `http://localhost:3000/events?city=some-city`. The rest of the url is not included in the redirect.

<!--
> Provide a clear and concise description of the issue
-->

### What was the expected behavior?
I should be redirected to the correct url which includes all the url/query string params.

I checked the network tab on Chrome and this is the url requested when I'm being redirected to the login page: `http://localhost:3000/api/auth/login?returnTo=/events?city=some-city&start=xxxx-xx-xx&end=xxxx-xx-xx`

I expect the `returnTo` url param to equal `/events?city=some-city&start=xxxx-xx-xx&end=xxxx-xx-xx` but that is not the case. There are actually 3 url params here:

- `returnTo: /events?city=some-city`
- `start: xxxx-xx-xx`
- `end: xxxx-xx-xx`

The `returnTo` value will only include the url up to the first url/query string param.
<!--
> Tell us about the behavior you expected to see
-->

### Environment

<!--
> Please provide the following:
-->

- **Version of this library used:** 1.3.0
- **Which framework are you using, if applicable:**next 10.0.7

### Additional contract requirements

- The `returnTo` value placed in the login redirect must be URL-encoded, so that a value containing its own query string (for example `/events?city=some-city&start=xxxx-xx-xx&end=xxxx-xx-xx`) survives the round-trip and is recoverable as a single value via `URLSearchParams.get('returnTo')`.
- When `returnTo` is omitted on the client, the encoded value is the current route path (`router.asPath`, prefixed by `router.basePath` when one is set), including any query string.
- When `returnTo` is omitted on the server, the encoded value is `ctx.resolvedUrl`, including any query string.
