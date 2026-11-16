Rule proposal: vue/v-text-no-child-content
**Please describe what the rule should do:**

When using the `v-text` directive, the element's inner content gets overwritten by the result of the `v-text` expression.

**What category should the rule belong to?**

[ ] Enforces code style (layout)
[x] Warns about a potential error (problem)
[ ] Suggests an alternate way of doing something (suggestion)
[ ] Other (please specify:)

This might just belong to the layout category, not sure.

**Provide 2-3 code examples that this rule should warn about:**

```vue
<template>
  <!-- ✓ GOOD -->
  <div v-text="foo"></div>

  <!-- ✗ BAD -->
  <div v-text="foo">{{ bar }}</div>
</template>
```

**Additional context**

I'm in the process of localizing an app, and stumbled upon a few elements which already used `v-text`, but *also* had child content:

```vue
<template>
  <label class="control-label col-sm-3" v-text="fields.name.label">
    Name
  </label>
</template>
```

This isn't really a problem, just unnecessary and confusing.
