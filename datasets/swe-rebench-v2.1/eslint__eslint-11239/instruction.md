Assignment to ternary expression using function parameter as condition triggers no-param-reassign
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

* **ESLint Version:** 5.9.0
* **Node Version:** 8.12.0
* **npm Version:** 6.4.1

**What parser (default, Babel-ESLint, etc.) are you using?** babel-eslint

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
{
    "parser": "babel-eslint",
    "extends": "airbnb",
    "env": {
        "browser": true
    },
    "rules": {
        "jsx-a11y/click-events-have-key-events": "off",
        "jsx-a11y/no-static-element-interactions": "off",
        "react/jsx-one-expression-per-line": [true, { "allow": "literal" }],
        "no-restricted-syntax": ["error", "ForInStatement", "LabeledStatement", "WithStatement"]
    }
}
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
function test(arg) {
  const array = [[1], [2]];
  (arg ? array[0] : array[1])[0] = 3;
  return array;
}
```

<!-- Paste the command you used to run ESLint: -->
```bash
yarn eslint src/
```

**What did you expect to happen?**
The above code should not emit lint errors.

**What actually happened? Please include the actual, raw output from ESLint.**
`error  Assignment to property of function parameter 'arg'     no-param-reassign`

**Are you willing to submit a pull request to fix this bug?**
Will try if possible.
