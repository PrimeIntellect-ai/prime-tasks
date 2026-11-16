Rule change request: indent: allow "off" for "outerIIFEBody"
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for requesting a rule change. If you are here for another reason, please see below:

    1. To report a bug: https://eslint.org/docs/developer-guide/contributing/reporting-bugs
    2. To propose a new rule: https://eslint.org/docs/developer-guide/contributing/new-rules
    3. To request a change that is not a bug fix, rule change, or new rule: https://eslint.org/docs/developer-guide/contributing/changes
    4. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**What rule do you want to change?** [indent](https://eslint.org/docs/rules/indent)

**Does this change cause the rule to produce more or fewer warnings?** Fewer warnings when applied (but the default behavior would be the same)

**How will the change be implemented? (New option, new default behavior, etc.)?** New option, default behavior unchanged

Several options for the `indent` rule accept the string `"off"` to disable the check and let the user do it however they want. But a few of them do not, such as `"outerIIFEBody"`. I would like to be able to set `"outerIIFEBody"` to `"off"`. Currently I have to choose between 0 or 1 but both choices enforce something, and I don't want to enforce anything.

Also, I find it curious that several of the options support the `"off"` setting but only `"outerIIFEBody"` and a few others don't.

**Please provide some example code that this change will affect:**

<!-- Put your code examples here -->
```js
// File 1
(function() {
    a();
)();

// File 2
(function() {
b();
)();
```

**What does the rule currently do for this code?** One of the files will cause a warning, depending whether I choose 0 or 1 for the `"outerIIFEBody"` rule.

**What will the rule do after it's changed?** With the `"off"` option, eslint would not give a warning for any of those cases, while still checking the other indentation rules for the other options.

**Are you willing to submit a pull request to implement this change?** Sadly I don't have time for this at the moment...
