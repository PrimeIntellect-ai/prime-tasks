no-extra-parens incorrectly reports returned IIFE
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for bug reports. If you are reporting a bug, please continue on. If you are here for another reason, please see below:

    1. To propose a new rule: http://eslint.org/docs/developer-guide/contributing/new-rules
    2. To request a change: http://eslint.org/docs/developer-guide/contributing/changes
    3. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**

* **ESLint Version:** 4.5.0
* **Node Version:** 8.1.3
* **npm Version:** 5.3.0

**What parser (default, Babel-ESLint, etc.) are you using?**
default

**Please show your full configuration:**
<details>
<summary>Configuration</summary>

```sh
node node_modules/eslint/bin/eslint.js --no-eslintrc --rule '{"wrap-iife": [2, "any"], "no-extra-parens": 2, "no-trailing-spaces": 2, "quotes":[2, "double"]}' --fix test/compiled.js
```
</details>

**What did you do? Please include the actual source code causing the issue.**

<!-- Paste the source code below: -->
```js
(function() {
    // trailing spaces
    console.log('quotes');

    // extra parens
    return (function() {
        // trailing spaces
        console.log('quotes');
    }());
})();
```

**What did you expect to happen?**
Fix option to be executed on nested iife

**What actually happened? Please include the actual, raw output from ESLint.**
When applying the command line above on the code above, quotes fix is applied on the top iife but not on the neted iife.

Without the `wrap-iife` everything is fine.

I haven't tested if the fix is not applied only for those specified rules.

On v4.5.0 here is the output
```sh
  6:12  error  Gratuitous parentheses around expression  no-extra-parens
  8:21  error  Strings must use doublequote              quotes
```

On v3.19.0 here is the output
```sh
  6:12  error  Gratuitous parentheses around expression  no-extra-parens
  7:30  error  Trailing spaces not allowed               no-trailing-spaces
  8:21  error  Strings must use doublequote              quotes
```
