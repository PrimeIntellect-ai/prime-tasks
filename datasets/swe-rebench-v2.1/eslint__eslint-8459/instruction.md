no-unused-vars doesn't detect destructured variables if the object pads another param
**Tell us about your environment**

* **ESLint Version:** 3.19.0
* **Node Version:** 6
* **npm Version:** 3

**What parser (default, Babel-ESLint, etc.) are you using?** babel-eslint

**Please show your full configuration:**
```
"no-unused-vars" : "warn",
```

**What did you do? Please include the actual source code causing the issue.**

Paste this into the [demo](http://eslint.org/demo/):

```js
(function ({ a }, b ) {
    return b;
})();
```

**What did you expect to happen?**

`a` should be detected as being unused.

**What actually happened? Please include the actual, raw output from ESLint.**

`a` passed, because I think it assumes the first parameter (the `{ a }` object) to be padding the `b` param.
