ESLint crash with prefer-object-spread
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for bug reports. If you are here for another reason, please see below:

    1. To propose a new rule: https://eslint.org/docs/developer-guide/contributing/new-rules
    2. To request a rule change: https://eslint.org/docs/developer-guide/contributing/rule-changes
    3. To request a change that is not a bug fix, rule change, or new rule: https://eslint.org/docs/developer-guide/contributing/changes
    4. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**

* **ESLint Version:** 5.2.0
* **Node Version:** v10.7.0
* **npm Version:** 6.1.0

**What parser (default, Babel-ESLint, etc.) are you using?**
I can reproduce this with the default parser, and with babel-eslint. I haven't tried other alternatives.

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
{
  "root": true,
  "rules": {
    "prefer-object-spread": 1
  }
}
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
Object.assign({
});
```

<!-- Paste the command you used to run ESLint: -->
```bash
./node_modules/.bin/eslint src
```

**What did you expect to happen?**
```
.../src/test.js
1:1  warning  Use an object literal instead of `Object.assign`. eg: `{ foo: bar }`  prefer-object-spread

✖ 1 problem (0 errors, 1 warning)
  0 errors and 1 warning potentially fixable with the `--fix` option.
```
**What actually happened? Please include the actual, raw output from ESLint.**
```
Fix objects must not be overlapped in a report.
AssertionError [ERR_ASSERTION]: Fix objects must not be overlapped in a report.
    at mergeFixes (/mnt/c/test/node_modules/eslint/lib/report-translator.js:150:9)
    at normalizeFixes (/mnt/c/test/node_modules/eslint/lib/report-translator.js:180:16)
    at args (/mnt/c/test/node_modules/eslint/lib/report-translator.js:278:18)
    at Object.report (/mnt/c/test/node_modules/eslint/lib/linter.js:830:41)
    at Program (/mnt/c/test/node_modules/eslint/lib/rules/prefer-object-spread.js:249:33)
    at listeners.(anonymous function).forEach.listener (/mnt/c/test/node_modules/eslint/lib/util/safe-emitter.js:45:58)
    at Array.forEach (<anonymous>)
    at Object.emit (/mnt/c/test/node_modules/eslint/lib/util/safe-emitter.js:45:38)
    at NodeEventGenerator.applySelector (/mnt/c/test/node_modules/eslint/lib/util/node-event-generator.js:251:26)
    at NodeEventGenerator.applySelectors (/mnt/c/test/node_modules/eslint/lib/util/node-event-generator.js:280:22)
```
