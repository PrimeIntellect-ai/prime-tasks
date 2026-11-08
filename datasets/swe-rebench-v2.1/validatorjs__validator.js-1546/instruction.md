isFQDN returns false for a valid FQDN
**Describe the bug**

Expected result is `true` but it returns `false`.

**Examples**

```sh
> require('is-fqdn')('12345.xyz')
true
> require('validator').isFQDN('12345.xyz')
false
```

**Additional context**
Validator.js version: Latest
Node.js version: LTS
OS platform: macOS
