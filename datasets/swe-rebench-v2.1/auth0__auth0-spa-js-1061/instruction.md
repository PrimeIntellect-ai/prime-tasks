Invalid State error with Nuxt, custom callback page and url-encoded characters
<!--
**Please do not report security vulnerabilities here**. The [Responsible Disclosure Program](https://auth0.com/whitehat) details the procedure for disclosing security issues.

**Thank you in advance for helping us to improve this library!** Please read through the template below and answer all relevant questions. Your additional work here is greatly appreciated and will help us respond as quickly as possible. For general support or usage questions, use the [Auth0 Community](https://community.auth0.com/) or [Auth0 Support](https://support.auth0.com/). Finally, to avoid duplicates, please search existing Issues before submitting one here.

By submitting an Issue to this repository, you agree to the terms within the [Auth0 Code of Conduct](https://github.com/auth0/open-source-template/blob/master/CODE-OF-CONDUCT.md).
-->

### Describe the problem

I tried to implement a custom callback URL to allow for adjusted error handling in a Nuxt.js SPA.
Long story short: Nuxt.js seams to normalize the URL and to replace `%3D` by `=` in `location.href`.

Using the Vue.js integration works when using `createAuth0` as `handleRedirectCallback` is called _before_ that normalization.
When calling `handleRedirectCallback` from inside a Vue.js component that normalization has happened and the replacement causes the state from the transaction to not match that from the URL.

I believe this to be an error in auth0-spa-js due to the way it reads the URL.
The `Invalid State` error should happen whenever `=` characters are encoded in the state and those characters are replaced by anything before `handleRedirectCallback` is called.

**What I found out about the auth0 implementation:**

The `Invalid State` error is thrown in https://github.com/auth0/auth0-spa-js/blob/master/src/Auth0Client.ts#L513.
[HIDDEN]

`=` chars in the value should be very common, as the values are just base64 encoded random strings ( https://github.com/auth0/auth0-spa-js/blob/master/src/Auth0Client.ts#L293 ).

### What was the expected behavior?

The auth0 SDK should not fail if any middleware replaces query parameters by their URL-Decoded representation. This replacement might be done for human readability.

<!-- Tell us about the behavior you expected to see -->

### Reproduction

- Try to Login via the Auth0 SDK
- Replace `%3D` with `=` in the URL before calling `handleRedirectCallback`
- call `handleRedirectCallback`

<!--
> Detail the steps taken to reproduce this error, and whether this issue can be reproduced consistently or if it is intermittent.
> **Note**: If clear, reproducable steps or the smallest sample app demonstrating misbehavior cannot be provided, we may not be able to follow up on this bug report.

- Step 1..
- Step 2..
- ...
-->

**Can the behavior be reproduced using the [SPA SDK Playground](https://github.com/auth0/auth0-spa-js/blob/master/DEVELOPMENT.md#the-sdk-playground)?**

<!--
If so, provide steps:

> Where applicable, please include:
>
> - The smallest possible sample app that reproduces the undesirable behavior
> - Log files (redact/remove sensitive information)
> - Application settings (redact/remove sensitive information)
> - Screenshots
-->

### Environment

<!--
> Please provide the following:
-->

- **Version of `auth0-spa-js` used:** 1.22.5 (but behaviour shouldn't be changed as the respective code stayed the same)
- **Which browsers have you tested in?**  Chrome
- **Which framework are you using, if applicable (Angular, React, etc):** Vue.js with Nuxt 3
- **Other modules/plugins/libraries that might be involved:** @auth0/auth0-vue
