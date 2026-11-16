`spaced-comment` should allow line ending after markers
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
[spaced-comment](https://eslint.org/docs/rules/spaced-comment)

**Does this change cause the rule to produce more or fewer warnings?**
fewer

**How will the change be implemented? (New option, new default behavior, etc.)?**
default behavior

**Please provide some example code that this change will affect:**

<!-- Put your code examples here -->
```js
/* eslint spaced-comment: ["error", "always", { "line": { "markers": ["/", "#region", "#endregion"] } }] */
/* eslint no-trailing-spaces: ["error"] */

//#region blah
const answer = 42;
//#endregion

console.log(answer);
```

**What does the rule currently do for this code?**

> 6:1  error  Expected space or tab after '//#endregion' in comment  spaced-comment

using `--fix` cannot fix it (since there are no possible auto fix)

**What will the rule do after it's changed?**

pass without tip an error

**Are you willing to submit a pull request to implement this change?**

Maybe no

----

`spaced-comment` does allow line ending after `//` without using markers. And this behavior should be applied to markers too imo.

### Additional contract requirements

- The marker-only exemption applies to both line comments (`//`) and block comments (`/* ... */`): when the entire content of a comment is exactly equal to one of the configured markers, the rule ignores that comment.
- Markers can be configured globally with `markers`, or per comment type with `line.markers` and `block.markers`.
- A comment whose content only begins with a marker but contains additional characters is still subject to the normal spacing rule.
- The default marker `*` (used for JSDoc comments) participates in the exemption like any other marker.


- For `//#endregionfoo` with `#endregion` configured in `line.markers` under `always`, report exactly `Expected space or tab after '//#endregion' in comment.`
