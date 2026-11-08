Bug: Validation Error with @stoplight/spectral-rulesets 1.19.0
**Describe the bug**
After upgrading to `@stoplight/spectral-rulesets` version 1.19.0, we encountered a validation error that was not present in version 1.18.1.

The error message indicates a problem with `spectral`, specifically a `TypeError: Cannot read properties of null (reading 'type')`.

```
[ERROR] There was a problem with spectral.
[ERROR] Cannot read properties of null (reading 'type')
[ERROR] Additional error details:
[ERROR] TypeError: Cannot read properties of null (reading 'type')
at [HIDDEN] (eval at query (/data/node_modules/nimma/dist/legacy/cjs/core/index.js:66:71), <anonymous>:10:31)
at eval (eval at query (/data/node_modules/nimma/dist/legacy/cjs/core/index.js:66:71), <anonymous>:182:41)
at _traverseBody (/data/node_modules/nimma/dist/legacy/cjs/runtime/traverse.js:13:5)
at _traverse (/data/node_modules/nimma/dist/legacy/cjs/runtime/traverse.js:41:7)
at _traverseBody (/data/node_modules/nimma/dist/legacy/cjs/runtime/traverse.js:17:5)
at _traverse (/data/node_modules/nimma/dist/legacy/cjs/runtime/traverse.js:41:7)
at _traverseBody (/data/node_modules/nimma/dist/legacy/cjs/runtime/traverse.js:17:5)
at _traverse (/data/node_modules/nimma/dist/legacy/cjs/runtime/traverse.js:41:7)
at _traverseBody (/data/node_modules/nimma/dist/legacy/cjs/runtime/traverse.js:17:5)
at _traverse **(/data/node_modules/nimma/dist/legacy/cjs/runtime/traverse.js:41:7)
```

**To Reproduce**

1. Upgrade to `@stoplight/spectral-rulesets` version 1.19.0.
2. Run the OpenAPI validation using `ibm-openapi-validator` or `spectral`.
3. Observe the validation error

**Expected behavior**
The OpenAPI validation should pass without any errors, as it did with `@stoplight/spectral-rulesets` version 1.18.1.

### Additional contract requirements

- OpenAPI validation must complete without throwing a `TypeError` when traversal encounters `null` values while reading `type`; applicable validation diagnostics should still be produced.
