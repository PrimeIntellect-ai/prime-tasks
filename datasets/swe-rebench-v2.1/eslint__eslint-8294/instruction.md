operator-assignment fix is breaking the code
**Tell us about your environment**

* **ESLint Version:** v3.18.0
* **Node Version:** v7.7.2
* **npm Version:** v4.1.2

**What parser (default, Babel-ESLint, etc.) are you using?**
default

**Please show your full configuration:**
```js
module.exports = {
    root: true,
    parserOptions: {
        ecmaVersion: 8,
    },
    rules: {
        'operator-assignment': [2, 'always'],
    },
};
```

**What did you do? Please include the actual source code causing the issue.**
#### test.js
```js
tmp = tmp + (2 * options.x[y]);
```

#### `$ eslint test.js --fix`

**What did you expect to happen?**
I expected the fix function to fix the code.

**What actually happened? Please include the actual, raw output from ESLint.**
Instead, it broke the code.
#### `$ eslint test.js --fix > output.txt`
```js
c:\nodejs\test\test.js
  1:25  error  Parsing error: Unexpected token ;

✖ 1 problem (1 error, 0 warnings)
```

#### test.js
```js
tmp += (2 * options.x[y];
```

It seems, that the rule doesn't handle braces properly.

### Additional contract requirements

- When `operator-assignment` is configured as `always`, fixing `x = x + (y)` must produce exactly `x += (y)`.
