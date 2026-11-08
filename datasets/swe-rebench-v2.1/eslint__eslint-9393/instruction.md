indent rule: ignoreNodes not working as expected in "tab" mode
I have a proposed fix for this, which I’ll send as a pull request. But I don’t think the bug itself has been reported yet, hence the below.

<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for bug reports. If you are reporting a bug, please continue on. If you are here for another reason, please see below:

    1. To propose a new rule: https://eslint.org/docs/developer-guide/contributing/new-rules
    2. To request a change: https://eslint.org/docs/developer-guide/contributing/changes
    3. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**

* **ESLint Version:** 4.8.0
* **Node Version:** 8.1.2
* **npm Version:** 5.4.2

**What parser (default, Babel-ESLint, etc.) are you using?** default

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
{
    "rules": {
        "indent": ["error", "tab", {
            "ignoredNodes": [ "VariableDeclarator" ]
        }]
    }
}
```

</details>

**What did you do? Please include the actual source code causing the issue.**

<!-- Paste the source code below: -->
```js
/* eslint indent: [ "error", "tab", { "ignoredNodes": [ "VariableDeclarator" ] } ] */
var x = 1,
    y = 2;
```

**What did you expect to happen?**
No error, since VariableDeclarator nodes are ignored.

**What actually happened? Please include the actual, raw output from ESLint.**

```
$ eslint --no-eslintrc dent.js

/Users/robin/Desktop/dent.js
  3:1  error  Expected indentation of 4 tabs but found 4 spaces  indent

✖ 1 problem (1 error, 0 warnings)
  1 error, 0 warnings potentially fixable with the `--fix` option.
```
