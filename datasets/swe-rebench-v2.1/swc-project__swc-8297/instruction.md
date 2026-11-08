jsc.paths regression in 1.3.79
### Describe the bug

swc re-writes import paths by following symlinks, it seems. I believe this is a regression from one of the changes @realtimetodie made when we originally got SWC working under Bazel.

It now looks like:

```
require("../../../../../../../private/var/tmp/_bazel_alexeagle/43e97bf6681e7317438fd77d405a1c4b/sandbox/darwin-sandbox/181/execroot/aspect_rules_swc/examples/paths/src/modules/moduleA");
```

Minimal repro:

1. clone https://github.com/aspect-build/rules_swc
2. `npx @bazel/bazelisk build --subcommands examples/paths:compile`
3. Open `bazel-bin/examples/paths/src/index.js` and you'll see the `require` path is relative
4. update `LATEST_SWC_VERSION = "v1.3.78"` to v1.3.79 in `swc/repositories.bzl`
5. repeat step 2 to build again
6. Look at the same index.js file and the require path now contains an absolute path to the root of the filesystem

If you need the minimal repro to not involve Bazel, we can engineer one that creates a similar symlink tree to reproduce the problem without it.
> Note, this is my fourth attempt to file an issue here, see prior attempt #8264.

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

https://github.com/aspect-build/rules_swc/pull/216/files

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

```
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
var moduleA_1 = require("@modules/moduleA");
(0, moduleA_1.moduleA)();
```

### Actual behavior

SWC 1.3.79 produces

```
const _moduleA = require("../../../../../../../shared/cache/bazel/user_base/09a27d1eeea3b44d1580773090924b4d/sandbox/linux-sandbox/629/execroot/aspect_rules_swc/examples/paths/src/modules/moduleA");
```

### Version

1.3.79

### Additional context

In 1.3.78 this worked, so https://github.com/swc-project/swc/pull/7852 is the likely culprit, as @kdy1 agrees https://github.com/swc-project/swc/issues/8258#issuecomment-1804883347
