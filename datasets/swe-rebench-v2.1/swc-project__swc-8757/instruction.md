jsc.paths regression in 1.3.79 with symlinks
### Describe the bug

This issue still exists with a more accurate bazel use case: https://github.com/swc-project/swc/issues/8265. See the [latest change](https://github.com/alexeagle/swc_8265_repro/commit/16bfa92286bdafe5dc48ead53c9b4177ce603fbb) to reproduce it.

See https://github.com/jbedard/swc/commit/08db61738cec601fa873734757f1eee71ed5225a for a new test that should reproduce it, but I haven't finished the rust setup to actually compile+run this test yet.

### Input code

```typescript
import { moduleA } from "@modules/moduleA";

moduleA();
```


### Config

```json
{
  "jsc": {
    "parser": {
      "syntax": "typescript"
    },
    "target": "es2021",
    "baseUrl": "./src",
    "paths": {
      "@modules/*": [
        "./modules/*"
      ]
    }
  },
  "module": {
    "type": "commonjs"
  },
  "sourceMaps": true
}
```


### Playground link (or link to the minimal reproduction)

https://github.com/alexeagle/swc_8265_repro/

### SWC Info output

swc-darwin-arm64 --version
SWC 0.91.64

### Expected behavior

SWC 1.3.78 produces

```
const _moduleA = require("./modules/moduleA/index");
```

In https://github.com/swc-project/swc/issues/8258 you suggested that we compare with what tsc produces. As I understand it, typescript never attempts to re-write import/require statements. So the result is here

https://github.com/aspect-build/rules_swc/pull/216/files#diff-e3a9eafb3b943b9863d6cea0b348d4ef40bc1b7bb5867a38ac889fcacea0cbf4R3

"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
var moduleA_1 = require("@modules/moduleA");
(0, moduleA_1.moduleA)();

### Actual behavior

SWC 1.3.79 - 1.4.3+ produces:

```
const _moduleA = require("../../../../../../../shared/cache/bazel/user_base/09a27d1eeea3b44d1580773090924b4d/sandbox/linux-sandbox/629/execroot/aspect_rules_swc/examples/paths/src/modules/moduleA");
```

### Version

1.3.79

### Additional context

See https://github.com/swc-project/swc/issues/8265

https://github.com/swc-project/swc/commit/7dfdc1221890d373d2e6caf52bc8dee8c20765ca fixed the original example in the [original repo](https://github.com/alexeagle/swc_8265_repro/tree/f1b6331f8fee3ad85d418fb1d5a5e20408b7ab3a).

However another example that is closer aligned with what actually occurs in bazel reproduces the issue, essentially just another layer of symlinks: https://github.com/alexeagle/swc_8265_repro/commit/16bfa92286bdafe5dc48ead53c9b4177ce603fbb

### Additional contract requirements

- For the symlink scenario described above, the emitted output must contain the exact text `require("./modules/moduleA")`, and must not be rewritten to an absolute sandbox or cache path.
