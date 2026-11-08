Cannot read properties of null (reading 'get')
### Current behavior

When calling the `getParsedSpec()` method of an `useOpenapi` instance, I get the following error:

```
Uncaught (in promise) TypeError: Cannot read properties of null (reading 'get')
    at P8e (vitepress-openapi.es.js:68526:53)
    at r (vitepress-openapi.es.js:68540:18)
    at r (vitepress-openapi.es.js:68542:18)
    at r (vitepress-openapi.es.js:68537:18)
    at r (vitepress-openapi.es.js:68542:18)
    at r (vitepress-openapi.es.js:68542:18)
    at r (vitepress-openapi.es.js:68542:18)
    at r (vitepress-openapi.es.js:68542:18)
    at I8e (vitepress-openapi.es.js:68546:10)
    at Object.i [as getParsedSpec] (vitepress-openapi.es.js:68894:22)
```

### Desired behavior

_No response_

### Reproduction

_No response_

### Steps to reproduce

The open api json can be found here: https://api-docs.tacticaldefense.software/openapi.json

Minimal code to reproduce:

```
import { theme, useOpenapi } from 'vitepress-openapi'
import spec from 'openapi.json' assert { type: 'json' }

const openapi = useOpenapi({ spec })
openapi.getParsedSpec();
```

### Logs and Error Messages

_No response_

### Other Information

I noticed that `@trojs/openapi-dereference` is currently on v0.2.4, but your packages.json file includes 0.2.3... maybe as easy as upgrading the version?

### Additional contract requirements

- `getParsedSpec()` must not throw when the supplied spec cannot be parsed (for example when a `$ref` cannot be resolved). In that case it falls back to the original, unparsed spec and returns it.
