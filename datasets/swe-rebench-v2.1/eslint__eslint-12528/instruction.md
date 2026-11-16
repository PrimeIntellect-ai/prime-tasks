camelcase: Option to ignore imports
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
`camelcase`

**Does this change cause the rule to produce more or fewer warnings?**
Fewer

**How will the change be implemented? (New option, new default behavior, etc.)?**

New option: `ignoreImports`: `true`/`false`, `default`: Debatable. I would say `true` by default because if the code is in your control, eslint would then only flag the declaration and not where it's imported.
Could possibly accept a string/regexp array to only ignore certain modules.

Existing option: `allow` (string/regexp array) somehow check these against the module token of an import (ex: `import { SomeType } from "react"` -> "react") rather than a check on the variable itself. For generated codes/types/etc this will not work well.

**Please provide some example code that this change will affect:**

<!-- Put your code examples here -->
```js
import { Some_apolloGenerated_Type } from "./__generated__/graphql-types.ts"; // generated code from apollo codegen
```
This could be aliased but this code is generated so it's basically futile. Plus it would be hard to come up with aliases for types corresponding to graphql queries/results and their inner types.

**What does the rule currently do for this code?**
Flags generated types from apollo code gen as violating the rule. These types are dynamically generated based on graphql queries which is the reason for a mix of underscores and camel casing.

**What will the rule do after it's changed?**
Ignore imports, either selectively or fully.

**Are you willing to submit a pull request to implement this change?**
No

### Additional contract requirements

- The `ignoreImports` option is a boolean option that defaults to `false`.
- When `ignoreImports` is `true`, `camelcase` does not report violations for bindings introduced by named import specifiers, including when the imported name is given a local alias.
