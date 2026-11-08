Clearcookie Doesn't Respect AUTH0_COOKIE_SAME_SITE
### Describe the problem
It seems that the `clearCookie` function used to remove the `appSession` cookie doesn't respect the `AUTH0_COOKIE_SAME_SITE` environment variable.

This means that if you set `AUTH0_COOKIE_SAME_SITE=none` to support cross-origin requests, users can log in, but when they try to logout, the `appSession` cookie isn't cleared.

### What was the expected behavior?

The `clearCookie` function should respect `AUTH0_COOKIE_SAME_SITE` when being used to clear `appSession`.

### Environment

- **Version of this library used:** 1.6.1
