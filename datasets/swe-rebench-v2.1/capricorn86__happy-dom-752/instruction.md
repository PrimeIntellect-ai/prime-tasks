toggleAttribute is not a function
**Describe the bug**
When attempting to access function `toggleAttribute` after `.querySelector`, an error is displayed:

```
container.toggleAttribute('disabled');
          ^

TypeError: container.toggleAttribute is not a function
    at file:///D:/Projects/happ-dom-repro1/index.js:9:11
    at ModuleJob.run (node:internal/modules/esm/module_job:193:25)
    at async Promise.all (index 0)
    at async ESMLoader.import (node:internal/modules/esm/loader:530:24)
    at async loadESM (node:internal/process/esm_loader:91:5)
    at async handleMainPromise (node:internal/modules/run_main:65:12)

Node.js v18.12.0
```

According to MDN, this function should be supported:
https://developer.mozilla.org/en-US/docs/Web/API/Element/toggleAttribute

**To Reproduce**
Run this code with `node index.js` after basing it off the basic example:

```js
import { Window } from 'happy-dom';

const window = new Window();
const document = window.document;

document.body.innerHTML = '<div class="container"></div>';

const container = document.querySelector('.container');
container.toggleAttribute('disabled');
```

**Expected behavior**
Attributes should be toggle on/off as expected of the spec from MDN.

**Device:**
 - OS: Windows 11

### Additional contract requirements

- Add a public method `toggleAttribute(name: string, force?: boolean)` on `Element` (in `packages/happy-dom/src/nodes/element/Element.ts`).
- With no `force` argument, the named attribute is toggled: it is added when absent and removed when present.
- With `force` set to `true`, the named attribute is ensured to be present.
- With `force` set to `false`, the named attribute is ensured to be absent.
- Return `true` when the attribute is present after the operation, and `false` when it is absent.
