False positive for `enforce-store-naming-convention` in `attach`
In the following cases, where a Store is _created_ in `attach` argument `source`, the rule `enforce-store-naming-convention` has a false positive.

Minimal reproduction:

```ts
const testFx = attach({
  source: createStore(0),
  effect: createEffect()
})
```

<img width="920" alt="issue-1" src="https://github.com/effector/eslint-plugin/assets/29187880/7c34f58e-9d80-4ad1-b530-9d8bac645497">

---

Other examples:

```ts
import { attach, combine, createStore, createEffect } from "effector";

const combineFx = attach({
  source: {
    value: combine(),
  },
  effect: createEffect()
})

const createStoreFx = attach({
  source: {
    value: createStore(0),
  },
  effect: createEffect()
})
```

In all of these, a prefix/suffix is erroneously suggested.

---

A real-life example where this is _not_ an error - a `combine` is used to prepare data for the effect.

**Versions:**

ESLint: `8.51.0`
eslint-plugin-effector: `0.11.0` (latest)
