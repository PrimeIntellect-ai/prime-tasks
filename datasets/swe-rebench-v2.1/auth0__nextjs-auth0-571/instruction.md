Checks.state argument is missing when trying to sign in inside an IFrame
### Description

> I am facing the error `Checks.state argument is missing` when i try sign in inside an IFrame. I checked some similar errors where env variables were misconfigured, but i think this is not my case since the authentication flow works fine in outside IFrame.

> The problem happens in the first login attempt, if the user already is logged the redirect works as expected.

### Reproduction

> - Create an application and install @auth0/nextjs-auth0
> - Setup environment variables
> - Instantiate application inside an IFrame
> - Sign in

### Environment

> Please provide the following:

- **Version of this library used:** 1.5.0
- **Next JS version:** 11.1.0

### Additional contract requirements

- For code-flow login requests, the transient `state` cookie must use the configured session cookie `sameSite` value: it defaults to `'lax'`, and when configured as `'none'` over HTTPS, the cookie must be Secure. With the default `'lax'` setting over HTTP, the cookie must not be Secure.
