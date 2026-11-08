`no-self-compare` does not handle complex expressions correctly
<!--
This template is for bug reports. If you are reporting a bug, please continue on. If you are here for another reason, please see below:

1. To propose a new rule: http://eslint.org/docs/developer-guide/contributing/new-rules
2. To request a change: http://eslint.org/docs/developer-guide/contributing/changes
3. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**

* **ESLint Version:** master
* **Node Version:** 7.2.0
* **npm Version:** 3.10.9

**What parser (default, Babel-ESLint, etc.) are you using?**

**Please show your full configuration:**

(none)

**What did you do? Please include the actual source code causing the issue.**

<!-- Paste the source code below: -->
```js
/* eslint no-self-compare: error */

foo.bar === foo.bar;
```

**What did you expect to happen?**

I expected ESLint to report an error for the self-comparison.

**What actually happened? Please include the actual, raw output from ESLint.**

No errors were reported.

I'm marking this as "evaluating" since I'm not sure whether it's intended behavior.

### Additional contract requirements

- The rule must report a comparison between two identical member-access expressions, such as `foo.bar === foo.bar`.
- The reported message must be exactly `Comparing to itself is potentially pointless.`
- The error must be reported on the comparison expression itself (node type `BinaryExpression`).
