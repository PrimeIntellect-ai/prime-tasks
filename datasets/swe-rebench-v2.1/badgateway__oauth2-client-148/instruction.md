Support response_mode=fragment
When passing response_mode=fragment to the autorization code flow request, most OAuth 2.0 and OIDC servers will respond with the code, state etc encoded as a URL fragment instead of query params.

This has the security benefit of not showing up in the server logs because fragments are not sent to the server. Especially important when using a CDN or other external service to host the frontend, which usually shouldn't have access to sensitive credentials.

It would be good if GetAuthorizeUrlParams would have an additional attrubute `response_mode` which can be set to `"query"` or `"fragment"`. getTokenFromCodeRedirect would also need to be able to handle this kind of response.

### Additional contract requirements

- The authorization request parameters accept an option named `responseMode` (the camelCase form of `response_mode`), which may be set to `'query'` or `'fragment'`. When it is set to `'fragment'`, the authorization URL produced for the authorization-code flow includes the `response_mode=fragment` parameter.
- The authorization-code client exposes a method `validateResponse(url: string|URL, params: {state?: string})` that synchronously parses the redirect URI and returns an object `{ code: string; scope?: string[] }`. It supports response parameters encoded either in the query string or in the URL fragment. If `params.state` is supplied and does not match the `state` returned in the redirect, it throws an error.
