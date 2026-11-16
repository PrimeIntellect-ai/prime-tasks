allowAfterThisConstructor for no-underscore-dangle
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for requesting a rule change. If you are here for another reason, please see below:

    1. To report a bug: https://eslint.org/docs/developer-guide/contributing/reporting-bugs
    2. To propose a new rule: https://eslint.org/docs/developer-guide/contributing/new-rules
    3. To request a change that is not a bug fix, rule change, or new rule: https://eslint.org/docs/developer-guide/contributing/changes
    4. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

Like many, I've been using the `no-underscore-dangle` method to enforce the style of prefixing "private" members with underscores. It's nice in that it flags anytime such properties are accessed, and the `allowAfterThis` and `allowAfterSuper` rules make possible to work with these properties inside a class.

I have found an additional case that would be nice to allow: when an instance method or constructor wants to invoke a "private" static method. To make this possible without having to disable the rule on a case-by-case basis, I'd like to add an option to allow underscore dangles when referencing properties on `this.constructor`.

**What rule do you want to change?**

`no-underscore-dangle`

**Does this change cause the rule to produce more or fewer warnings?**

Fewer, optionally.

**How will the change be implemented? (New option, new default behavior, etc.)?**

New option.

**Please provide some example code that this change will affect:**

<!-- Put your code examples here -->
```js
var a = this.constructor.foo_;
this.constructor._bar();
```

**What does the rule currently do for this code?**

Produces the following warnings/errors:
`Unexpected dangling '_' in 'foo_'
`Unexpected dangling '_' in '_bar'

**What will the rule do after it's changed?**
Allows suppression in this case, if new `allowAfterThisConstructor` option is set to true.

**Are you willing to submit a pull request to implement this change?**

Yes, will be creating it shortly.
