5.0.0 - Crash with prefer-const rule where code contains array destructuring assignment with 'ignored values'
This is a minimal reproduction for a bug I've found in `eslint@5.0.0`. As far as I can tell the example code below is valid JavaScript (see https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Destructuring_assignment#Ignoring_some_returned_values).
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

* **ESLint Version:** 5.0.0
* **Node Version:** 8.11.0
* **npm Version:** 5.6.0
* **yarn Version:** 1.7.0

**What parser (default, Babel-ESLint, etc.) are you using?** default

**Please show your full configuration:**

<!-- Paste your configuration below: -->
```json
{
    "parserOptions": {
        "ecmaVersion": 2018
    },
    "rules": {
      "prefer-const": 1
    }
}

```


**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
const b = [1, 2];
let a;

[, a] = b;

```

<!-- Paste the command you used to run ESLint: -->
```bash
cd eslint-5-array-destructuring-assignment-bug
yarn eslint .
```

**What did you expect to happen?**
eslint would lint my project

**What actually happened? Please include the actual, raw output from ESLint.**
eslint did not lint my project and threw a TypeError from one of its built-in rules (`prefer-const`)
```
Cannot read property 'name' of null
TypeError: Cannot read property 'name' of null
    [HIDDEN]
    at listeners.(anonymous function).forEach.listener (/node_modules/eslint/lib/util/safe-emitter.js:45:58)
    at Array.forEach (<anonymous>)
    at Object.emit (/node_modules/eslint/lib/util/safe-emitter.js:45:38)
    at NodeEventGenerator.applySelector (/node_modules/eslint/lib/util/node-event-generator.js:251:26)
    at NodeEventGenerator.applySelectors (/node_modules/eslint/lib/util/node-event-generator.js:280:22)
```

### Additional contract requirements

- With `prefer-const` enabled, linting valid JavaScript that uses an array destructuring assignment with ignored elements must complete without throwing.
