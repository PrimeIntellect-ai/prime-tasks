"use" doesn't behave as expected as an ES6 named export
The following code throws an error:

```js
import sinonChai from "sinon-chai";
import {expect, use} from "chai";

use(sinonChai);
```

The reason it throws an error is because the necessary `this` binding is lost when calling `use` via the above syntax as opposed to calling it via `chai.use(sinonChai)`.

I'd argue that it's unexpected and undesirable for a singleton module to utilize `this` in such a way.

One possible solution might be to change [use](https://github.com/chaijs/chai/blob/2194a89e0290a3152446995afe877d4248256c91/lib/chai.js#L38-L45) from:

```js
exports.use = function (fn) {
  if (!~used.indexOf(fn)) {
    [HIDDEN]
    used.push(fn);
  }

  [HIDDEN]
};
```

[HIDDEN]

### Additional contract requirements

- Calling `use` as a detached function, including as an ES6 named import, must register the plugin against the Chai API without relying on the call-site `this` binding.
