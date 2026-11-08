Rule Proposal: vue/no-constant-condition
<!--
  Before proposing new rule, please make sure it hasn't been posted already.
  You can see all open propositions here:
  https://github.com/vuejs/eslint-plugin-vue/issues?q=is%3Aopen+is%3Aissue+label%3A%22new+rule+proposition%22
-->

**Please describe what the rule should do:**
like [no-constant-condition](https://eslint.org/docs/rules/no-constant-condition) in eslint, but works with `v-if`/`v-show`.

**What category should the rule belong to?**
<!-- (place an "X" next to just one item) -->
[ ] Enforces code style (layout)
[x] Warns about a potential error (problem)
[ ] Suggests an alternate way of doing something (suggestion)
[ ] Other (please specify:)

**Provide 2-3 code examples that this rule should warn about:**

```vue
<div v-if="true"></div>
<div v-if="true || prop1"></div>
```

**Additional context**
<!-- Add any other context or screenshots about the feature request here. -->
