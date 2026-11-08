wrap-regex doesn't work in some expression
**Tell us about your environment**

* **ESLint Version:** 5.0.1
* **Node Version:** 8.11.3
* **npm Version:** 5.6.0

**What parser (default, Babel-ESLint, etc.) are you using?**

default

**Please show your full configuration:**

```js
module.exports = {
  rules: {
    'wrap-regex': 2,
  },
}
```

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

```js
// sample.1
const bar = /abc/.test(foo)

// sample.2
if (/abc/.test(foo)){
  baz()
}
```

```bash
eslint --fix test.js
```

**What did you expect to happen?**

ESLint should report errors in both samples, but in fact, sample 2 passed the lint, no error reports.

**What actually happened? Please include the actual, raw output from ESLint.**

```js
// sample.1 fixed correct
const bar = (/abc/).test(foo)

// sample.2 not fixed
if (/abc/.test(foo)){
  baz()
}
```

**Online demo**
[demo](https://eslint.org/demo/#eyJ0ZXh0IjoiY29uc3QgYmFyID0gL2FiYy8udGVzdChmb28pXG5cbmlmICgvYWJjLy50ZXN0KGZvbykpe1xuICBiYXooKVxufSIsIm9wdGlvbnMiOnsicGFyc2VyT3B0aW9ucyI6eyJlY21hVmVyc2lvbiI6OSwic291cmNlVHlwZSI6Im1vZHVsZSIsImVjbWFGZWF0dXJlcyI6e319LCJydWxlcyI6eyJ3cmFwLXJlZ2V4IjoyfSwiZW52Ijp7fX19)
