`lib/util/version.js:31:31` is not compatible with processors with virtual filename
A lot of rules are incompatible.

```log
Oops! Something went wrong! :(

ESLint: 7.22.0

TypeError: Error while loading rule 'react/display-name': Provided basedir "/Users/JounQin/Workspaces/GitHub/eslint-mdx/README.md" is not a directory, or a symlink to a directory
Occurred while linting /Users/JounQin/Workspaces/GitHub/eslint-mdx/README.md/3_3.js
    at Function.resolveSync [as sync] (/Users/JounQin/Workspaces/GitHub/eslint-mdx/node_modules/eslint-plugin-react/node_modules/resolve/lib/sync.js:91:24)
    at detectReactVersion (/Users/JounQin/Workspaces/GitHub/eslint-mdx/node_modules/eslint-plugin-react/lib/util/version.js:31:31)
    at getReactVersionFromContext (/Users/JounQin/Workspaces/GitHub/eslint-mdx/node_modules/eslint-plugin-react/lib/util/version.js:55:25)
    at Object.testReactVersion (/Users/JounQin/Workspaces/GitHub/eslint-mdx/node_modules/eslint-plugin-react/lib/util/version.js:124:35)
    at usedPropTypesInstructions (/Users/JounQin/Workspaces/GitHub/eslint-mdx/node_modules/eslint-plugin-react/lib/util/usedPropTypes.js:285:48)
    at Function.componentRule (/Users/JounQin/Workspaces/GitHub/eslint-mdx/node_modules/eslint-plugin-react/lib/util/Components.js:966:37)
    at createRuleListeners (/Users/JounQin/Workspaces/GitHub/eslint-mdx/node_modules/eslint/lib/linter/linter.js:761:21)
    at /Users/JounQin/Workspaces/GitHub/eslint-mdx/node_modules/eslint/lib/linter/linter.js:931:31
    at Array.forEach (<anonymous>)
    at runRules (/Users/JounQin/Workspaces/GitHub/eslint-mdx/node_modules/eslint/lib/linter/linter.js:876:34)
```

Can we add a check like following?

https://github.com/prettier/eslint-plugin-prettier/pull/401/files#diff-e9a90fe7b2d3420b8e5f64e24d5f56ffe6383e47b07461172cc29ed21b768905R79-R94
