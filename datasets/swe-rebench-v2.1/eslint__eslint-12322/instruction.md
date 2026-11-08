no-useless-rename should also report pattern properties with default values
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

no-useless-rename

**Does this change cause the rule to produce more or fewer warnings?**

more

**How will the change be implemented? (New option, new default behavior, etc.)?**

New default behavior, because I think this is more a bug than an enhancement.

But, there is a question would it be okay for a semver-minor release.

**Please provide some example code that this change will affect:**

<!-- Put your code examples here -->
```js
/* eslint no-useless-rename:error */

const { a: a = 1 } = foo;
```

**What does the rule currently do for this code?**

Nothing.

**What will the rule do after it's changed?**

Error, same as for `const { a: a } = foo;` and autofix to:

```js
/* eslint no-useless-rename:error */

const { a = 1 } = foo;
```

**Are you willing to submit a pull request to implement this change?**

Yes.
