Rule Proposal: `vue/no-restricted-component-names`
<!--
  Before proposing new rule, please make sure it hasn't been posted already.
  You can see all open propositions here:
  https://github.com/vuejs/eslint-plugin-vue/issues?q=is%3Aopen+is%3Aissue+label%3A%22new+rule+proposition%22
-->

**Please describe what the rule should do:**
<!-- A clear and concise description of what the rule should do. -->

Restrict some component names via a list of pattern.

**What category should the rule belong to?**
<!-- (place an "X" next to just one item) -->
[ ] Enforces code style (layout)
[x] Warns about a potential error (problem)
[ ] Suggests an alternate way of doing something (suggestion)
[ ] Other (please specify:)

**Provide 2-3 code examples that this rule should warn about:**

Options:

```json
{
  "vue/no-restricted-component-names": ["error", "Foo", "/^Baz(One|Two)/"]
}
```

```vue
<script>
<!-- ✗ BAD -->
export default {
  name: 'Foo'
}

<!-- ✗ BAD -->
export default {
  name: 'BazTwo'
}

<!-- ✓ GOOD-->
export default {
  name: 'Allow'
}
</script>
```

**Additional context**
<!-- Add any other context or screenshots about the feature request here. -->

Related https://github.com/vuejs/eslint-plugin-vue/issues/2180#issuecomment-1551298495.

### Additional contract requirements

- Each entry in the rule's options is either a literal component name, which must equal the component's `name`, or a regular expression written in `/.../` form, which is tested against the component's `name`.
- A component whose `name` matches at least one configured entry is reported.
- A component whose `name` matches none of the configured entries is not reported, including when the rule is configured with entries.
- The `name` is checked wherever a component declares it in its options object, including `defineOptions` in `<script setup>`.
