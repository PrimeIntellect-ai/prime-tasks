Convert space-within-parens to space-in-parens
### 🐛 Bug Report

-   `tslint-to-eslint-config` version: 0.5.0
-   ESLint version: 6.8.0
-   Node version: 11.10.0

#### Actual Behavior

TSLint rule `space-within-parens` will be converted to `@typescript-eslint/space-within-parens` (see #184 and #193), but there is no rule for that (anymore?) in the `@typescript-eslint` plugin. Instead ESLint's core rule `space-in-parens` should be used, as stated [here](https://github.com/typescript-eslint/typescript-eslint/blob/master/packages/eslint-plugin/ROADMAP.md#style) as well.

#### Expected Behavior

TSLint rule `space-within-parens` will be converted to `space-in-parens`.
