Add support for Promise.allSettled() and Promise.any()
### Description

I want the plugin to add support for Promise.allSettled() and Promise.any().
Those Promise features were added in ES2020 and later, but this plugin doesn't seem to support them yet.

https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/allSettled
https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/any

### Steps to Reproduce

```js
/* eslint promise/valid-params: error */

Promise.all([p1, p2]); // OK
Promise.all(p1, p2); // NG

Promise.any([p1, p2]); // OK
Promise.any(p1, p2); // NG: False negative

Promise.allSettled([p1, p2]); // OK
Promise.allSettled(p1, p2); // NG: False negative
```

[Online DEMO](https://ota-meshi.github.io/eslint-plugin-promise-playground/#eyJjb2RlIjoiLyogZXNsaW50IHByb21pc2UvdmFsaWQtcGFyYW1zOiBlcnJvciAqL1xuXG5Qcm9taXNlLmFsbChbcDEsIHAyXSk7IC8vIE9LXG5Qcm9taXNlLmFsbChwMSwgcDIpOyAvLyBOR1xuXG5Qcm9taXNlLmFueShbcDEsIHAyXSk7IC8vIE9LXG5Qcm9taXNlLmFueShwMSwgcDIpOyAvLyBORzogRmFsc2UgbmVnYXRpdmVcblxuUHJvbWlzZS5hbGxTZXR0bGVkKFtwMSwgcDJdKTsgLy8gT0tcblByb21pc2UuYWxsU2V0dGxlZChwMSwgcDIpOyAvLyBORzogRmFsc2UgbmVnYXRpdmVcbiIsInJ1bGVzIjp7fX0=)

**Expected behavior:** [What you expect to happen]

I expect to be warned even if I use the new API.

**Actual behavior:** [What actually happens]

The plugin does not support new APIs.

### Versions

[Please fill this in if you are submitting a bug report]

- Node version: v18.4.0
- ESLint version: v8.24.0
- eslint-plugin-promise version: v6.0.1

### Additional Information

[Any additional information, configuration or data that might be necessary to
reproduce the issue]
