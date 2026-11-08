Only allow specific compontent names
<!--
  Before proposing new rule, please make sure it hasn't been posted already.
  You can see all open propositions here:
  https://github.com/vuejs/eslint-plugin-vue/issues?q=is%3Aopen+is%3Aissue+label%3A%22new+rule+proposition%22
-->

**Please describe what the rule should do:**
<!-- A clear and concise description of what the rule should do. -->

Enforce consistency component name prefix. This rule should accept options to enforce component matches names or name patterns.

**What category should the rule belong to?**
<!-- (place an "X" next to just one item) -->
[x] Enforces code style (layout)
[ ] Warns about a potential error (problem)
[ ] Suggests an alternate way of doing something (suggestion)
[ ] Other (please specify:)

**Provide 2-3 code examples that this rule should warn about:**

```vue
<!-- Good -->
<keep-alive></keep-alive> <!-- builtin -->
<button/> <!-- html tag -->
<foo-button/> <!-- allowed with option `/^foo\-/` -->

<!-- Bad -->
<bar-button/>
```

**Additional context**
<!-- Add any other context or screenshots about the feature request here. -->
N/A

### Additional contract requirements

- The rule's public identifier is `restricted-component-names`.
- Configure allowed component names with an `allow` array of strings. A plain string allows that literal name; a string written as a regular-expression literal, such as `'/^foo-/'`, allows names matching that pattern. Component names not allowed by this option are reported.
- Built-in Vue components and native template elements are not restricted component names.
