`useUnit` object form adds `(payload: void) => void` for `Event<void>` instead of `() => void`
**What is the current behavior:**

https://www.typescriptlang.org/play?#code/JYWwDg9gTgLgBAbzgYygUwIYzQUQG5oB28AvnAGZQQhwDka55ayM0tA3AFCiSyJwBXAM5oAqoWCkKVGvUbNWUALToMLDp07IIhIfDQFiAQTgBeFKuz4iMADx4IwACYA+ABQBKTdt3wkhCBgAeQBrODJzYTEJGDd-QNCALjgDGxMSDy4fPTgIMMiRcUk3VOMvTgBhakhCGziUDAAbRoAjNRDkgOCwjMrqnTqkZCbW9uS88PLyAUIWYB04KvAB4nrh5rbkHuShkc2OuBLDGGSZkICAd0IPMxc4B2dJxE44V7gAene4MAwhIU4SJogA

```ts
import { createEvent } from 'effector';
import { useUnit } from 'effector-react';

const eventA = createEvent<void>()

const { notOk } = useUnit({ notOk: eventA });
const ok = useUnit(eventA)

Component({ callback: notOk })
Component({ callback: ok })

function Component({ callback }: { callback: (event: unknown) => void }) {
    // ...
}
```

**What is the expected behavior:**

Same behaviour in object form and in simple form, no error. It is current behaviour of `useEvent`

**Which versions of effector packages, and which browser and OS are affected by this issue? Did this work in previous versions of effector?:**

`effector-react` with `useUnit`
