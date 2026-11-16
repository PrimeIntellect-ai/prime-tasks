Rule proposal: vue/prefer-use-template-ref
**Please describe what the rule should do:**
Vue 3.5 released a new preferred method of binding to template refs, `useTemplateRef`. This rule suggests using the new API over the old plain ref style. It has better dev tools support, supports dynamic keys and is more self-documenting.

**What category should the rule belong to?**
<!-- (place an "X" next to just one item) -->
[ ] Enforces code style (layout)
[ ] Warns about a potential error (problem)
[X] Suggests an alternate way of doing something (suggestion)
[ ] Other (please specify:)

**Provide 2-3 code examples that this rule should warn about:**

```vue
<template>
  <input ref="input">
</template>

<script setup>
<!-- BAD -->
const input = ref();

<!-- GOOD -->
import { useTemplateRef } from 'vue'

const input = useTemplateRef('input')
</script>
```

**Additional context**
https://vuejs.org/api/composition-api-helpers.html#usetemplateref Docs about the API
https://blog.vuejs.org/posts/vue-3-5#usetemplateref Reasoning for the the new recommendation.

### Additional contract requirements

- The rule must declare its ESLint category as a suggestion, i.e. its rule metadata `meta.type` is `'suggestion'`.
