`prefer-object-spread` rule should not report `Object.assign({}, ...array)`
**Tell us about your environment**

* **ESLint Version:** 5.0.0-alpha.3
* **Node Version:** 10.1.0
* **npm Version:** 5.6.0

**What parser (default, Babel-ESLint, etc.) are you using?** default

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```yml
root: true
parserOptions:
  ecmaVersion: 2018
  sourceType: script
rules:
  prefer-object-spread: 2
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
const objects = array.map(mapObject)
const var = Object.assign({}, ...objects)
```

<!-- Paste the command you used to run ESLint: -->
```bash
eslint .
```

**What did you expect to happen?**
`Object.assign()` should not be reported as wrong. There is no way to use object spreads in this example because `objects` is an array of objects. It is not possible to use object spreads to concatenate an array of objects (e.g. `[{ ... }, { ... }]`) into a single object.

The `prefer-object-spread` rule should not report a linting error when one of the arguments to `Object.assign()` uses an array spread.

This also means the above line with `--fix` would be converted to `{ ...objects }` which is incorrect.

**What actually happened? Please include the actual, raw output from ESLint.**
`Object.assign()` was reported as wrong.
