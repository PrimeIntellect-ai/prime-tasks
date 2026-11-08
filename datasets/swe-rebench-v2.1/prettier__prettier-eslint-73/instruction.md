Custom Fallback Options if a Setting is Not Inferrable from ESlint
This is, admittedly, purely needed for prettier-atom. In prettier-atom, if you turn ESlint integration on, it's going to stay on regardless of whether the project you've got open actually has all prettier-related rules set in their config.

If the project doesn't have an ESlint rule needed for prettier, users are wanting to fall back to the prettier setting they've set inside of their prettier-atom config instead of falling back to the default value for that prettier option (which is how it currently works if I'm not mistaken). If I could pass fall-back options to prettier-eslint when using it to format, that would be great. Note that this is different than the current API which only allows manual overrides as opposed to fall-backs.

Any thoughts on adding this to the API?

### Additional contract requirements

- Add a public function `getOptionsForFormatting(eslintConfig, prettierOptions = {}, fallbackPrettierOptions = {})` in `src/utils.js`. It returns an object `{eslint, prettier}`, where `prettier` is the final Prettier options object after merging values derived from the ESLint rules, explicit `prettierOptions`, and `fallbackPrettierOptions`.
- Add a public function `format(options)` in `src/index.js` that accepts a `fallbackPrettierOptions` key on its options object and uses those values when formatting.
- `fallbackPrettierOptions` supplies a Prettier value for a setting only when that setting cannot be inferred from the ESLint configuration (i.e. the corresponding ESLint rule is not configured). When the corresponding ESLint rule is configured, the value derived from it is used instead of the fallback.
- Explicit `prettierOptions` values take precedence over values derived from ESLint and over `fallbackPrettierOptions`.
