Return auth URL for usage with manual browser redirects
**Please do not report security vulnerabilities here**. The [Responsible Disclosure Program](https://auth0.com/whitehat) details the procedure for disclosing security issues.

**Thank you in advance for helping us to improve this library!** Please read through the template below and answer all relevant questions. Your additional work here is greatly appreciated and will help us respond as quickly as possible. For general support or usage questions, use the [Auth0 Community](https://community.auth0.com/) or [Auth0 Support](https://support.auth0.com/). Finally, to avoid duplicates, please search existing Issues before submitting one here.

By submitting an Issue to this repository, you agree to the terms within the [Auth0 Code of Conduct](https://github.com/auth0/open-source-template/blob/master/CODE-OF-CONDUCT.md).

### Description

> Provide a clear and concise description of the issue, including what you expected to happen.

My app runs ionic/react with capacitor and the auth0-spa-js sdk.  I am attempting to use the capacitor "Browser" plugin to open the auth0 universal login, because utilizing loginWithRedirect() causes the app to open safari externally.  The problem is, I cannot find how to retrieve the constructed URL loginWithRedirect uses.  It would be nice to have the auth0-spa-js library return the URL that loginWithRedirect generates so we can utilize custom plugins for redirect.  Am I going about this the wrong way?

### Reproduction

> Detail the steps taken to reproduce this error, what was expected, and whether this issue can be reproduced consistently or if it is intermittent.
>
> Where applicable, please include:
>
> - Code sample to reproduce the issue
> - Log files (redact/remove sensitive information)
> - Application settings (redact/remove sensitive information)
> - Screenshots

Run auth0-spa-js sdk with ionic/react quickstart and call loginWithRedirect().  Observe redirection outside of app instead of in SafariViewController.

### Environment

> Please provide the following:

- **Version of this library used:** 1.5.0
- **Version of the platform or framework used, if applicable:** @ionic/react@4
- **Other relevant versions (language, server software, OS, browser):**
- **Other modules/plugins/libraries that might be involved:**

### Additional contract requirements

- Add a public method `buildAuthorizeUrl(options?: RedirectLoginOptions): Promise<string>` on the `Auth0Client` class exported from `src/Auth0Client.ts`. It accepts the same options as `loginWithRedirect` (including `redirect_uri`, `appState`, `fragment`, and other authorize parameters such as `scope`, `audience` and `connection`) and defaults to an empty object when omitted.
- `buildAuthorizeUrl` resolves to the full `/authorize` URL. The URL includes the query parameters for the request (such as `client_id`, `scope`, `response_type=code`, `response_mode=query`, `redirect_uri` and any custom authorize parameters), a generated `state`, `nonce` and PKCE `code_challenge` with `code_challenge_method=S256`, the client telemetry, and the optional `fragment` appended after a `#`. Calling it must not perform any navigation.
- `handleRedirectCallback` must accept an optional `url: string` argument. When a URL is provided the authentication response is parsed from that URL; when it is omitted the current `window.location.href` is used.
