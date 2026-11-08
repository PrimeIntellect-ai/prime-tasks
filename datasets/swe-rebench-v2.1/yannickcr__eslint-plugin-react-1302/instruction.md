no-literals: only check strings
[HIDDEN] with the new `{ "noStrings": true }` option (https://github.com/yannickcr/eslint-plugin-react/pull/1202) I'm getting errors for explicitly set boolean and number props `booleanprop={true}` `numberprop={100}`

### Additional contract requirements

- With `noStrings` enabled, the rule should report string literals in JSX but must not report JSX expressions merely because they explicitly supply boolean or numeric values.
