cookieauth plugin with autoRenew renews token constantly
<!-- Issues will be CLOSED IMMEDIATELY if the following template is not completed. -->

## Bug Description
The cookieauth plugin with `autoRenew=true` can get the `TokenManager` into a state where it constantly renews the token. This happens if the `Max-Age` cookie header field is missing.

```
  cloudant:tokens:tokenmanager Auto renewing token now... +1ms
  cloudant:tokens:tokenmanager Starting token renewal. +0ms
  cloudant:tokens:tokenmanager Finished token renewal. +466ms
  cloudant:tokens:tokenmanager Renewing token in NaN milliseconds. +0ms
  cloudant:tokens:tokenmanager Auto renewing token now... +1ms
  cloudant:tokens:tokenmanager Starting token renewal. +0ms
  cloudant:tokens:tokenmanager Finished token renewal. +555ms
  cloudant:tokens:tokenmanager Renewing token in NaN milliseconds. +0ms
```

### 1. Steps to reproduce and the simplest code sample possible to demonstrate the issue
<!--
Outline the steps you take to make the problem happen.
Provide the simplest code sample you can, in context, that reproduces the issue.
-->
Connect using the cookieauth plugin and get a `Set-Cookie` HTTP header without the `Max-Age` field.

### 2. What you expected to happen
Cookie to be renewed after the `Max-Age` from the `Set-Cookie` header, or the `defaultMaxAgeSecs` if not present.

### 3. What actually happened
Cookie is renewed constantly

## Environment details
- Version(s) that are affected by this issue.
    > 4.2.2 and above
- Node.js version
    > any

### Additional contract requirements

- The `TokenManager` class exported from module `lib/tokens/TokenManager.js` provides a public method `startAutoRenew(defaultMaxAgeSecs)`. `defaultMaxAgeSecs` is an optional number of seconds used as the fallback maximum age when the `Set-Cookie` header does not contain a `Max-Age` attribute. The method returns no value.
