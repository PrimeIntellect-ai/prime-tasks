Rule Proposal: `vue/no-implicit-coercion`
<!--
  Before proposing new rule, please make sure it hasn't been posted already.
  You can see all open propositions here:
  https://github.com/vuejs/eslint-plugin-vue/issues?q=is%3Aopen+is%3Aissue+label%3A%22new+rule+proposition%22
-->

**Please describe what the rule should do:**

It would be nice to make the core rule [no-implicit-coercion](https://eslint.org/docs/rules/no-implicit-coercion) work in `<template>` expressions.

**What category should the rule belong to?**
<!-- (place an "X" next to just one item) -->
[] Enforces code style (layout)
[ ] Warns about a potential error (problem)
[X] Suggests an alternate way of doing something (suggestion)
[ ] Other (please specify:)

**Provide 2-3 code examples that this rule should warn about:**

```vue
<template>
  <div :data-foo="!!foo" />
  <div :data-foo="~foo.indexOf('.')" />
  <div :data-foo="+foo" />
  <div :data-foo="1 * foo" />
  <div :data-foo="'' + foo" />
  <div :data-foo="`` + foo" />
  <!-- if the `disallowTemplateShorthand` option is enabled -->
  <div :data-foo="`${foo}`" />
</template>
```

### Additional contract requirements

Expose this behavior as `vue/no-implicit-coercion`. Apply the core rule's implicit-coercion checks to Vue template expressions, including interpolations and directive expressions, as well as bound attributes. Shorthand coercions in those expressions should be reported according to the core rule's behavior and options.
