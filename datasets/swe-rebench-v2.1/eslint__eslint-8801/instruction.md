indent handles variable declarations incorrectly when the first declarator is on a new line
**Tell us about your environment**

* **ESLint Version: 4.0.0**
* **Node Version: 6.9.2**
* **npm Version: 5.0.3**

**What parser (default, Babel-ESLint, etc.) are you using?**

**Please show your full configuration:**

<!-- Paste your configuration below: -->
```
"rules": {
  "indent": [2, 2, {"SwitchCase": 1}],
}
```

**What did you do? Please include the actual source code causing the issue.**

<!-- Paste the source code below: -->
```js
const
  o = {
    foo: 'bar'
  },
  p = true;

console.log(o, p);
```

**What did you expect to happen?**

**What actually happened? Please include the actual, raw output from ESLint.**

```
test.js
  3:1  error  Expected indentation of 6 spaces but found 4  indent
  4:1  error  Expected indentation of 4 spaces but found 2  indent

✖ 2 problems (2 errors, 0 warnings)
  2 errors, 0 warnings potentially fixable with the `--fix` option
```

Works fine with eslint 3.x and if only one variable is declared at a time.

### Additional contract requirements

- Running `indent` with default options on a variable declaration that has several declarators, where the first declarator starts on a new line, must not report indentation errors for correctly indented code such as the example above. This includes `var`, `let` and `const` declarations whose declarators have multi-line object literal initializers.
