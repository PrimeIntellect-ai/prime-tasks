Certain valid patterns are not accepted by schema function
**Describe the bug**

In some cases, Ajv bails upon a valid pattern.
It's presumably an issue with Ajv, or, with the way we use Ajv.

**To Reproduce**

1. Run the following snippet
```js
const Ajv = require('ajv');
const ajv = new Ajv();
const assert = require('assert');

const schema = {
  type: 'string',
  pattern: '^[A-Za-z0-9\\-\\_]',
};

assert.ok(ajv.validate(schema, 'test-case-1'));
```
2. Exits with non-zero code

**Expected behavior**

Exits with a zero-code


Related to https://github.com/stoplightio/platform-internal/issues/7541
