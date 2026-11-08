3.16.0 regression: padded-blocks autofix can generate incorrect code
**Tell us about your environment**

* **ESLint Version:** 3.16.0
* **Node Version:** 6.9.1
* **npm Version:** 3.10.8

**What parser (default, Babel-ESLint, etc.) are you using?**
default

**Please show your full configuration:**

```
module.exports = {
  rules: {
    "padded-blocks": ['error', 'never'],
  }
};
```

(This is the value specified by eslint-config-airbnb.)

**What did you do? Please include the actual source code causing the issue.**

I ran `eslint --fix` on this source code:

```js
function f() { // a

  b;
}
```

**What did you expect to happen?**

I expected it to fix the formatting and generate correct code.

**What actually happened? Please include the actual, raw output from ESLint.**

eslint generated this output:
```
➜  eslint_test_3 git:(master) ./node_modules/.bin/eslint --fix test.js

/Users/alanpierce/code/eslint_test_3/test.js
  6:1  error  Parsing error: Unexpected token

✖ 1 problem (1 error, 0 warnings)
```

And the JS file was changed to have these contents:
```
function f() {
function f() { // a

  b;
}
```

This is a syntax error, so the file fails to parse after this change.

When I try this on eslint 3.15.0, it doesn't have any problems.

This is breaking the [coffeelint example build](https://github.com/decaffeinate/decaffeinate#status) for the decaffeinate project. The [lexical_linter.js](https://github.com/decaffeinate-examples/coffeelint/blob/decaffeinate/src/lexical_linter.js) file has two `static initClass` lines near the start, which causes a syntax error. (The example builds are a bit like eslint-canary for the decaffeinate project, and one of the conversion steps is to run `eslint --fix` on the resulting JS code.)
