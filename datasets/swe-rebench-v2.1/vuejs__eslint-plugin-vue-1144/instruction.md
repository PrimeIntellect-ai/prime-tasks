[FR] `inheritAttrs: false` when using `v-bind="$attrs"`
Components that inherit `$attrs` into a nested element in the component typically wouldn't want to get duplicated attributes applied to the top-level element. Might be a good linting rule to warn to apply `inheritAttrs: false` when it detects `v-bind="$attrs"` being used.

### Additional contract requirements

- The rule is published as `vue/no-duplicate-attr-inheritance` and implemented in the module `lib/rules/no-duplicate-attr-inheritance.js`.
- When the rule reports, the diagnostic message is exactly `Set "inheritAttrs" to false.`
- Report for a bare `v-bind="$attrs"` when attribute inheritance is enabled, including when `inheritAttrs` is omitted.
- Do not report for that binding when `inheritAttrs` is false.
