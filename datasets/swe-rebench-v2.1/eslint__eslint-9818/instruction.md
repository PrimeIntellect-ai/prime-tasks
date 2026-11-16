comment at end of line confuses indent's handling of ternary operator
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for bug reports. If you are reporting a bug, please continue on. If you are here for another reason, please see below:

    1. To propose a new rule: https://eslint.org/docs/developer-guide/contributing/new-rules
    2. To request a change: https://eslint.org/docs/developer-guide/contributing/changes
    3. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**

* **ESLint Version:** 4.13.1
* **Node Version:** 9.2.0

**What parser (default, Babel-ESLint, etc.) are you using?** babel-eslint

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
module.exports = {
  parser: 'babel-eslint',
  rules: {
    'indent': ['error', 2, { SwitchCase: 1 }]
  }
}
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
const obj = {
  foo () {
    return condition ? // comment
    1 :
      2
  }
}
```

<!-- Paste the command you used to run ESLint: -->
```bash
npx eslint path/to/file.js
```

**What did you expect to happen?**
`1` to be indented at the same level as `2`

**What actually happened? Please include the actual, raw output from ESLint.**
The source code above is formatted according to `eslint --fix`.

`indent` wants to indent the `1` at the same level as the `return` statement. Removing the `// comment` after the `?` clears `indent`'s confusion and it does put `1` at the same indent level as `2`.

Putting the `?` on the next line also works around the problem.
