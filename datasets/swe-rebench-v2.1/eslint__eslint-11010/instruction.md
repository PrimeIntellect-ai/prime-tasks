Location of `version` property is inconsistent between core APIs
In ESLint 4.6.1, we have a `version` property on `CLIEngine` and `Linter` indicating the version of ESLint being used. However, the `version` property appears in different places; it's placed on `CLIEngine` directly, but it's placed on *instances* of `Linter`.

```js
const eslint = require("eslint");

eslint.CLIEngine.version // 4.6.1
eslint.Linter.version // undefined

new eslint.CLIEngine().version // undefined
new eslint.Linter().version // 4.6.1
```

This happened because the `version` property was added when `Linter` was a singleton rather than a constructor, so users were previously expected to access `eslint.linter.version`.

This could be mildly annoying; for example, an integration that only has access to `Linter` (like https://eslint.org/demo) would need to create a throwaway instance of `Linter` to get the version.

I propose that we add `version` as a static property of `Linter`. We could also copy it to `Linter.prototype` to prevent integrations from breaking if they were checking for the `version` property on instances.
