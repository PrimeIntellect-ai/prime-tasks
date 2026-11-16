Support block-comment version of eslint-disable-line
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for bug reports. If you are reporting a bug, please continue on. If you are here for another reason, please see below:

    1. To propose a new rule: http://eslint.org/docs/developer-guide/contributing/new-rules
    2. To request a change: http://eslint.org/docs/developer-guide/contributing/changes
    3. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**

* **ESLint Version:** master
* **Node Version:** any
* **npm Version:** any

**What parser (default, Babel-ESLint, etc.) are you using?**
default

**Please show your full configuration:**

<!-- Paste your configuration below: -->
```
{ "rules": { "no-alert": [1] } }
```

**What did you do? Please include the actual source code causing the issue.**

<!-- Paste the source code below: -->
```js
/* eslint-disable-line */ alert(1);
```

**What did you expect to happen?**

It should work like in JSCS:
```js
/* jscs:ignore */ alert(1)
```

**What actually happened? Please include the actual, raw output from ESLint.**

Error reported.

### Additional contract requirements

- Block comments must support both the `eslint-disable-line` and the `eslint-disable-next-line` directives, in addition to the existing line-comment forms. For example, `/* eslint-disable-line no-alert */` suppresses the named rule(s) on the same line, and `/* eslint-disable-next-line no-alert */` suppresses the named rule(s) on the following line.
- A block-comment disable directive is recognized only when the entire comment is on a single physical line. A block comment whose directive text spans more than one line (for example `/* eslint-disable-line` followed by `no-alert */` on the next line) must not suppress any violation.
