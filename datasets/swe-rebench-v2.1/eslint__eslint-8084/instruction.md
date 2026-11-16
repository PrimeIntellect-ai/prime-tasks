unicode-bom fixer insert BOM in appropriate location
<!--
This template is for bug reports. If you are reporting a bug, please continue on. If you are here for another reason, please see below:

1. To propose a new rule: http://eslint.org/docs/developer-guide/contributing/new-rules
2. To request a change: http://eslint.org/docs/developer-guide/contributing/changes
3. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**
Win 10, 64bit
* **ESLint Version:** v.3.15.0
* **Node Version:** v.7.5.0
* **npm Version:** v.4.1.2
**What parser (default, Babel-ESLint, etc.) are you using?**
    default
**Please show your full configuration:**
<!-- Paste your configuration below: -->
```
"unicode-bom" :  "error"
```

**What did you do? Please include the actual source code causing the issue.**
I called `eslint --fix some.js`.
<!-- Paste the source code below: -->
```js
// Some comments.
function someFunction() {
    // some code...
}
```

**What did you expect to happen?**
```js
<U+FEFF>// Some comments.
function someFunction() {
    // some code...
}
```

**What actually happened? Please include the actual, raw output from ESLint.**
```js
// Some comments.
<U+FEFF><U+FEFF><U+FEFF><U+FEFF><U+FEFF><U+FEFF><U+FEFF><U+FEFF><U+FEFF><U+FEFF>function someFunction() {
    // some code...
}
```
