When a crash occurs, the error message is printed twice
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for bug reports. If you are reporting a bug, please continue on. If you are here for another reason, please see below:

    1. To propose a new rule: http://eslint.org/docs/developer-guide/contributing/new-rules
    2. To request a change: http://eslint.org/docs/developer-guide/contributing/changes
    3. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**

* **ESLint Version:** 4.2.0
* **Node Version:** 8.1.4
* **npm Version:** 5.0.3

**What parser (default, Babel-ESLint, etc.) are you using?**

default

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```yml
rules:
  no-restricted-syntax: [error, 'Invalid selector [[[[']
```

</details>

**What did you do? Please include the actual source code causing the issue.**

<!-- Paste the source code below: -->
```js
a;
```

**What did you expect to happen?**

The configuration isn't valid (it includes an invalid selector), so I expected ESLint to output an error message.

**What actually happened? Please include the actual, raw output from ESLint.**

ESLint outputted the same error message twice, once with the stack trace and once without:

<details>
<summary>Output</summary>

```
Syntax error in selector "Invalid selector [[[[" at position 18: Expected " ", "." or [^ [\],():#!=><~+.] but "[" found.
Error: Syntax error in selector "Invalid selector [[[[" at position 18: Expected " ", "." or [^ [\],():#!=><~+.] but "[" found.
    at tryParseSelector (/path/to/node_modules/eslint/lib/util/node-event-generator.js:163:19)
    at lodash.memoize.rawSelector (/path/to/node_modules/eslint/lib/util/node-event-generator.js:175:28)
    at memoized (/path/to/node_modules/lodash/lodash.js:10566:27)
    at NodeEventGenerator.eventNames.forEach.rawSelector (/path/to/node_modules/eslint/lib/util/node-event-generator.js:235:30)
    at Array.forEach (native)
    at new NodeEventGenerator (/path/to/node_modules/eslint/lib/util/node-event-generator.js:234:20)
    at Linter.verify (/path/to/node_modules/eslint/lib/linter.js:909:34)
    at processText (/path/to/node_modules/eslint/lib/cli-engine.js:203:31)
    at processFile (/path/to/node_modules/eslint/lib/cli-engine.js:245:18)
    at executeOnFile (/path/to/node_modules/eslint/lib/cli-engine.js:585:25)

```

</details>

This isn't specific to the `no-restricted-syntax` rule -- it seems to occur whenever any error is thrown from anywhere.

### Additional contract requirements

- When ESLint crashes with an uncaught error, the error message must appear exactly once in the command's output (stdout or stderr); it must not be printed twice.
- When no configuration file can be found, the diagnostic explaining that must be present in the command's output (stdout or stderr).
