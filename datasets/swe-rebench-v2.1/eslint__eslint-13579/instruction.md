Rule proposal: No useless template string, or prefer String()
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for new rule proposals. If you are proposing a new rule, please continue on. If you are here for another reason, please see below:

    1. To report a bug: https://eslint.org/docs/developer-guide/contributing/reporting-bugs
    2. To request a rule change: https://eslint.org/docs/developer-guide/contributing/rule-changes
    3. To request a change that is not a bug fix, rule change, or new rule: https://eslint.org/docs/developer-guide/contributing/changes
    4. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Please describe what the rule should do:**
Disallow useless template strings, such as `${x}`. The thing is this can be used as a way to cast a variable to string, which means the rule could instead be "prefer String()" or "prefer .toString()".

**What category of rule is this? (place an "X" next to just one item)**

[ ] Warns about a potential error (problem)
[X] Suggests an alternate way of doing something (suggestion)
[ ] Enforces code style (layout)
[ ] Other (please specify:)

**Provide 2-3 code examples that this rule will warn about:**

<!-- Put your code examples here -->
```js
const x = "soomething";
callAFunction(123, "mamamia", `${x}`);
```

```js
const x = 19
callAFunction(123, "mamamia", `${x}`);
```

**Why should this rule be included in ESLint (instead of a plugin)?**

Because eslint already had tons of `no-useless-something` rules, so this one would fit very well with the rest.

**Are you willing to submit a pull request to implement this rule?**
No unless you point me to the right resources and ask nicely and I have enough free time this week

### Additional contract requirements

The `no-implicit-coercion` rule gains a new boolean option named `disallowTemplateShorthand`, which defaults to `false`. When the option is omitted or set to `false`, template literals are not reported by this option.

When `disallowTemplateShorthand` is `true`, a template literal that contains exactly one expression and no surrounding static text (for example `` `${foo}` ``) is reported with the rule's `useRecommendation` message, recommending `String(expression)` (for example `String(foo)`). The report provides an automatic fix that replaces the whole template literal with `String(expression)`.

Tagged templates (for example `` tag`${foo}` ``), template literals with more than one expression (for example `` `${foo}${bar}` ``), and template literals with surrounding static text (for example `` `a${foo}` `` or `` `${foo}b` ``) are not reported. Escape sequences that produce no characters, such as a line continuation, do not count as surrounding static text.
