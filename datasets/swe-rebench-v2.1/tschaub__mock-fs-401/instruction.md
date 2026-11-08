`fs.existsSync` mock incorrectly throws `ENOTDIR` when the real `fs.existsSync` returns false
It looks like the `fs.existsSync` mock added in https://github.com/tschaub/mock-fs/pull/387 is in some cases inconsistent with the actual `fs.existsSync` behaviour.

Example (`index.js` file):
```js
import { default as mock } from "mock-fs";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

try {
  console.log(`native fs.existsSync('index.js/path'):`);
  console.log(`>`, fs.existsSync("index.js/path"));
  console.log();

  mock({ "index.js": mock.load(`${__dirname}/index.js`) });
  console.log(`mocked fs.existsSync('index.js/path'):`);
  console.log(`>`, fs.existsSync("index.js/path"));
  mock.restore();
} catch (e) {
  console.error(e);
}
```

Expected output
```
native fs.existsSync('index.js/path'):
> false

mocked fs.existsSync('index.js/path'):
> false
```

Actual output
```
native fs.existsSync('index.js/path'):
> false

mocked fs.existsSync('index.js/path'):
Error: ENOTDIR, not a directory 'index.js/path'
    at FileSystem.getItem (/Users/viktor/code/sandbox/mock-fs-exists-sync-issue/node_modules/mock-fs/lib/filesystem.js:128:15)
    at Binding.<anonymous> (/Users/viktor/code/sandbox/mock-fs-exists-sync-issue/node_modules/mock-fs/lib/binding.js:1488:31)
    at maybeCallback (/Users/viktor/code/sandbox/mock-fs-exists-sync-issue/node_modules/mock-fs/lib/binding.js:85:17)
    at Binding.exists (/Users/viktor/code/sandbox/mock-fs-exists-sync-issue/node_modules/mock-fs/lib/binding.js:1486:10)
    at Binding.existsSync (/Users/viktor/code/sandbox/mock-fs-exists-sync-issue/node_modules/mock-fs/lib/binding.js:1507:15)
    at Object.<anonymous> (/Users/viktor/code/sandbox/mock-fs-exists-sync-issue/node_modules/mock-fs/lib/index.js:39:39)
    at Module.existsSync (node:fs:292:18)
    at file:///Users/viktor/code/sandbox/mock-fs-exists-sync-issue/index.js:16:23
    at ModuleJob.run (node:internal/modules/esm/module_job:222:25)
    at async ModuleLoader.import (node:internal/modules/esm/loader:316:24) {
  code: 'ENOTDIR',
  errno: -20,
  path: 'index.js/path'
}
```
