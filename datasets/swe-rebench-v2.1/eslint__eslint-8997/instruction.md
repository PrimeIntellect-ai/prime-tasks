End location inference doesn't work for rules using the new-style context.report API
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for bug reports. If you are reporting a bug, please continue on. If you are here for another reason, please see below:

    1. To propose a new rule: http://eslint.org/docs/developer-guide/contributing/new-rules
    2. To request a change: http://eslint.org/docs/developer-guide/contributing/changes
    3. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**

* **ESLint Version:** 4.3.0
* **Node Version:** 8.2.0
* **npm Version:** 5.3.0

**What parser (default, Babel-ESLint, etc.) are you using?**

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
rules:
  no-whitespace-before-property: error
```

</details>

**What did you do? Please include the actual source code causing the issue.**

<!-- Paste the source code below: -->
```
echo 'foo .bar' | eslint --stdin --no-eslintrc --rule 'no-whitespace-before-property: error' --format json
```



**What did you expect to happen?**

I expected the resulting problem to have an `endLine` and `endColumn`, because the `no-whitespace-before-property` rule [reports a node](https://github.com/eslint/eslint/blob/2874d75ed8decf363006db25aac2d5f8991bd969/lib/rules/no-whitespace-before-property.js#L48).

**What actually happened? Please include the actual, raw output from ESLint.**

```
[{"filePath":"<text>","messages":[{"ruleId":"no-whitespace-before-property","severity":2,"message":"Unexpected whitespace before property bar.","line":1,"column":1,"nodeType":"MemberExpression","source":"foo .bar","fix":{"range":[3,5],"text":"."}}],"errorCount":1,"warningCount":0,"fixableErrorCount":1,"fixableWarningCount":0,"source":"foo .bar\n"}]
```

Note that there is no `endLine` and `endColumn`.

The issue is that the change in https://github.com/eslint/eslint/commit/b0c63f0a928cceff7cf6f060262dd7ac4bc0f8dc was incomplete. It modifies the logic in `lib/eslint.js` (which has now been renamed to `lib/linter.js`) to correctly handle the case where no location is provided. [HIDDEN] As a potentially separate fix, I think we should refactor the interaction between `Linter#report` and `RuleContext#report`. This bug occurred because the two methods don't have a clear separation of responsibilities with regard to handling locations that weren't provided by the rule.

### Additional contract requirements

- When a rule reports a node through the object-based `context.report` API without an explicit end location, the resulting lint message must include `endLine` and `endColumn` corresponding to the reported node’s end location.
