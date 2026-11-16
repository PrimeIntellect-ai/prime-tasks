[v4] indent: False positive with multi-line parenthesized function calls
**Tell us about your environment**

* **ESLint Version:** 4.1.0
* **Node Version:** 7.10.0
* **npm Version:** 4.2.0

**What parser (default, Babel-ESLint, etc.) are you using?**

default

**Please show your full configuration:**

```json
{
  "root": true,
  "parserOptions": {
    "ecmaVersion": 2017
  },
  "rules": {
    "indent": ["error", 2, {
      "SwitchCase": 1,
      "MemberExpression": 1,
      "FunctionDeclaration": {"parameters": 1},
      "FunctionExpression": {"parameters": 1},
      "CallExpression": {"arguments": 1}
    }]
  }
}
```

**What did you do? Please include the actual source code causing the issue.**

<!-- Paste the source code below: -->
```js
const str = (obj =>
  Object.keys(obj).join('')
)({
  k: 'v',
});
```

**What did you expect to happen?**

No errors

**What actually happened? Please include the actual, raw output from ESLint.**

```
4:1  error  Expected indentation of 4 spaces but found 2  indent
5:1  error  Expected indentation of 2 spaces but found 0  indent
```

The problem seems like it's being caused by the indentation of the arrow function.
If I use a normal function:

```js
const str = (function(obj) {
  return Object.keys(obj).join('')
})({
  k: 'v',
});
```

there are no errors.
