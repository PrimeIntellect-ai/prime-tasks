Support util.promisify on installed functions
* FakeTimers version : 6.0.1
* Environment   : Node v15.5.1

**What did you expect to happen?**

[`util.promisify`](https://nodejs.org/api/util.html#util_util_promisify_original) would work on `setTimeout` installed by FakeTimers as it does on the global `setTimeout`.

**What actually happens**

The Promise returned by the installed `setTimeout` is never resolved because the installed `setTimeout` does not have a [`promisify.custom`](https://nodejs.org/api/util.html#util_custom_promisified_functions) symbol property.

**How to reproduce**

```js
const { promisify } = require('util');
const FakeTimers = require("@sinonjs/fake-timers");

console.log('initial global.setTimeout', setTimeout[promisify.custom]);

const target = { Date };
FakeTimers.install({ target });
console.log('installed target.setTimeout', target.setTimeout[promisify.custom]);

FakeTimers.install();
console.log('installed global.setTimeout', setTimeout[promisify.custom]);
```
prints

    initial global.setTimeout [Function]
    installed target.setTimeout undefined
    installed global.setTimeout undefined

**Discussion**

This issue was noted by @joshua-barnett in https://github.com/sinonjs/fake-timers/pull/292#issuecomment-744443087.  I'm opening this issue to track it.

### Additional contract requirements

- `FakeTimers.withGlobal(target)` returns an object exposing an `install(options?)` method. Calling `install()` installs the fake timer functions on the supplied `target` object instead of the global object and returns a Clock. `util.promisify` must work on the `setTimeout` installed on that target, just as it does on the globally installed `setTimeout`.
