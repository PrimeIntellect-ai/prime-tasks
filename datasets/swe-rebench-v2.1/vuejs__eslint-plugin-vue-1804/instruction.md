Rule Proposal: disallow imports from @vue/* dependencies
<!--
  Before proposing new rule, please make sure it hasn't been posted already.
  You can see all open propositions here:
  https://github.com/vuejs/eslint-plugin-vue/issues?q=is%3Aopen+is%3Aissue+label%3A%22new+rule+proposition%22
-->

**Please describe what the rule should do:**
<!-- A clear and concise description of what the rule should do. -->
Disallow or warn about imports from `@vue/*` dependencies. Particularly when using Vue CLI and the build target is a library.

**What category should the rule belong to?**
<!-- (place an "X" next to just one item) -->
[ ] Enforces code style (layout)
[x] Warns about a potential error (problem)
[ ] Suggests an alternate way of doing something (suggestion)
[ ] Other (please specify:)

**Provide 2-3 code examples that this rule should warn about:**

```vue
<!-- Fail or Warn -->
import { computed } from "@vue/reactivity";

import {
  something,
  another,
} from "@vue/compiler-dom";
```

```vue
<!-- Pass -->
import { computed } from "vue";
```

**Additional context**
<!-- Add any other context or screenshots about the feature request here. -->
Full context can be found in [this issue I opened in the core repo](https://github.com/vuejs/core/issues/5327).

In short, using the `@vue/reactivity` import broke the components I was building for my UI library with Vue CLI and they were failing silently.

### Additional contract requirements

The rule reports imports and exports from exactly these prohibited modules:

- `@vue/runtime-dom`
- `@vue/runtime-core`
- `@vue/reactivity`
- `@vue/shared`

Other `@vue/*` packages (for example `@vue/compiler-dom`) are not reported. In particular, the `@vue/compiler-dom` import in the example above is not a reportable case, despite appearing under its “Fail or Warn” label.

The rule is named `vue/prefer-import-from-vue`.
