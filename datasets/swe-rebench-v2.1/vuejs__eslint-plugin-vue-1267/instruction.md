Rule proposal: `v-for-delimiter-style`
**Please describe what the rule should do:**
You can use both `v-for="x in xs"` and `v-for="x of xs"`. There should be a rule to enforce one of the styles (probably configurable).

**What category should the rule belong to?**
<!-- (place an "X" next to just one item) -->
- [X] Enforces code style
- [ ] Warns about a potential error
- [ ] Suggests an alternate way of doing something
- [ ] Other (please specify:)

**Provide 2-3 code examples that this rule should warn about:**
```vue
<!-- "vue/v-for-delimiter-style": ["warn", "in"] -->
<div v-for="x in xs" /><!-- GOOD -->
<div v-for="x of xs" /><!-- BAD -->

<!-- "vue/v-for-delimiter-style": ["warn", "of"] -->
<div v-for="x of xs" /><!-- GOOD -->
<div v-for="x in xs" /><!-- BAD -->
```

**Additional context**
See https://vuejs.org/v2/guide/list.html#Mapping-an-Array-to-Elements-with-v-for:

> You can also use `of` as the delimiter instead of `in`, so that it is closer to JavaScript’s syntax for iterators.
