Extend isUUID to support UUID-like values
**Describe the bug**

Since version 13.15.0 `isUUID` only supports UUID v1 through v8: https://github.com/validatorjs/validator.js/pull/2421

But there are systems that generate random hex values in the UUID format that do not correspond to UUID versions. Example: [FileMaker Get(UUID)](https://help.claris.com/en/pro-help/content/get-uuid.html).

These UUID-like values should also be (optional) recognized as valid to allow for more flexibility in usage. It would be awesome to allow them if "isUUID" is called with "all" or maybe there can be added a new version-string "like" or "hex"?

**Examples**

Example of a randomly generated hex value in the UUID format:

`04C5CA5B-BA81-964D-9097-88343F39FAED `

**Reproductions**

```
const validator = require('validator');
console.log(validator.isUUID('04C5CA5B-BA81-964D-9097-88343F39FAED')); // false
console.log(validator.isUUID('04C5CA5B-BA81-964D-9097-88343F39FAED', 'all')); // false
```

**Additional context**

Validator.js version: 13.15.0
Node.js version: 22
OS platform: linux, macOS
