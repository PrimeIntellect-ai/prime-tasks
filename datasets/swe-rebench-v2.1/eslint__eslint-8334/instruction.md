linter.verify mutates its config argument
<!--
This template is for bug reports. If you are reporting a bug, please continue on. If you are here for another reason, please see below:

1. To propose a new rule: http://eslint.org/docs/developer-guide/contributing/new-rules
2. To request a change: http://eslint.org/docs/developer-guide/contributing/changes
3. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**

* **ESLint Version:** master
* **Node Version:** 7.7.4
* **npm Version:** 4.1.2

**What did you do? Please include the actual source code causing the issue.**

<!-- Paste the source code below: -->
```js
const eslint = require("eslint");

const config = {};

eslint.linter.verify("foo", config);

console.log(config);
```

**What did you expect to happen?**

I expected `config` to still be an empty object.

**What actually happened? Please include the actual, raw output from ESLint.**

A `globals` property was added to `config`, so the output was:

```
{ globals: {} }
```

I ran into this issue when I tried to pass a config to `linter.verify` and then to `CLIEngine` afterwards. An error was thrown because `CLIEngine` expected an array of globals instead of an object, which was confusing because I hadn't originally specified `globals` at all.

I suspect this is the cause of https://github.com/eslint/eslint/issues/7967.
