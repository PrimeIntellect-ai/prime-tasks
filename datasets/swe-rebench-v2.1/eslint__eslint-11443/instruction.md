no-var fixed to incorrect code
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

* **ESLint Version:** v5.14.1/master
* **Node Version:** n/a
* **npm Version:** n/a

**What parser (default, Babel-ESLint, etc.) are you using?**
`@typescript-eslint/parser`
**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
{rules: {no-var: 2}}
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
declare var __IS_PRODUCTION__: boolean;
```

<!-- Paste the command you used to run ESLint: -->
```bash

```

**What did you expect to happen?**
not fixed to incorrect code

**What actually happened? Please include the actual, raw output from ESLint.**
```ts
let var __IS_PRODUCTION__: boolean;
```

**Are you willing to submit a pull request to fix this bug?**
yes

### Additional contract requirements

- When autofixing an ambient declaration such as `declare var ...`, preserve `declare` and change the `var` keyword to `let`. Do not disable the fix or produce malformed output such as `let var ...`.
