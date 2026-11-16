Warn about mixing logical and ternary operators
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for requesting a rule change. If you are here for another reason, please see below:

    1. To report a bug: https://eslint.org/docs/developer-guide/contributing/reporting-bugs
    2. To propose a new rule: https://eslint.org/docs/developer-guide/contributing/new-rules
    3. To request a change that is not a bug fix, rule change, or new rule: https://eslint.org/docs/developer-guide/contributing/changes
    4. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**What rule do you want to change?**
`no-mixed-operators`

**Does this change cause the rule to produce more or fewer warnings?**
more

**How will the change be implemented? (New option, new default behavior, etc.)?**
new option with default behaviour to warn

**Please provide some example code that this change will affect:**

<!-- Put your code examples here -->
```js
// what is priority of this? rule should warn of using brackets explicitly
obj.someValue || conditionSatisfied ? 'good' : 'bad'

// 1 option - rule should not warn
(obj.someValue || conditionSatisfied) ? 'good' : 'bad'

// 2 option - rule should not warn
obj.someValue || (conditionSatisfied ? 'good' : 'bad')
```

**What does the rule currently do for this code?**
it does not warn user about mixed logical and ternary expressions

**What will the rule do after it's changed?**
warn to use brackets around to make it explicit what the priority is

**Are you willing to submit a pull request to implement this change?**
nope, with this issue, I am just checking if this would make sense
Might be related to https://github.com/eslint/eslint/issues/7903

### Additional contract requirements

- The `?:` (ternary) operator is a valid operator value in the `groups` option of `no-mixed-operators`.
- When `?:` is listed in the same `groups` entry as a logical operator (`&&` or `||`), mixing a logical operator and a ternary operator without explicit parentheses is reported as an unexpected mix.
- Parentheses that make the grouping explicit are not reported, for example `(a || b) ? c : d` and `a || (b ? c : d)`.
- By default `?:` is not part of any operator group, so mixing logical and ternary operators is allowed unless the configuration includes `?:` in a group.
