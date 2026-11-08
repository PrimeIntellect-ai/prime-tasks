Do not generate re-export for type imports
<!--
If you are using swc at work, please considering adding your company to https://swc.rs/users/
If then, your issue will be fixed more quickly.
-->

**Input code**

```ts
import type { TestInfo } from './config'

export { TestInfo }
```

**Config**

```json
{
  "target": "es2020",
  "module": "commonjs"
}
```

**Expected**

```js
"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});

...
```

**Actually**

```js
"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});

exports.TestInfo = void 0;
exports.TestInfo = TestInfo;
...
```

**Version**
The version of @swc/core:

`1.2.84`

### Additional contract requirements

For the input above, with `target: es2020` and `module: commonjs`, the complete
generated output is exactly:

```js
"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
```

In particular, no `exports.TestInfo` re-export is generated.
