The camelcase rule does not allow leading/trailing underscores for variable names
**Tell us about your environment**

* **ESLint Version:** v4.13.0
* **Node Version:** v8.9.3
* **npm Version:** v5.5.1

**What parser (default, Babel-ESLint, etc.) are you using?**
default

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
{
    "parserOptions": {
        "ecmaVersion": 8,
        "sourceType": "module",
        "ecmaFeatures": {}
    },
    "rules": {
        "camelcase": 2
    },
    "env": {}
}
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

Contents of `test.js`:
<!-- Paste the source code below: -->
```js
function shouldAllowUndercoreVars() {
	let { _value } = this;
	return _value;
}
shouldAllowUndercoreVars()
```

Shell command used:
<!-- Paste the command you used to run ESLint: -->
```bash
eslint test.js
```

This is currently reproducible on the eslint demo site:
https://eslint.org/demo/#eyJ0ZXh0IjoiZnVuY3Rpb24gc2hvdWxkQWxsb3dVbmRlcmNvcmVWYXJzKCkge1xuXHRsZXQgeyBfdmFsdWUgfSA9IHRoaXM7XG5cdHJldHVybiBfdmFsdWU7XG59XG5zaG91bGRBbGxvd1VuZGVyY29yZVZhcnMoKSIsIm9wdGlvbnMiOnsicGFyc2VyT3B0aW9ucyI6eyJlY21hVmVyc2lvbiI6OCwic291cmNlVHlwZSI6Im1vZHVsZSIsImVjbWFGZWF0dXJlcyI6e319LCJydWxlcyI6eyJjYW1lbGNhc2UiOjJ9LCJlbnYiOnt9fX0=


**What did you expect to happen?**
I would have expected it to allow the variable name based on the [camelcase docs](https://eslint.org/docs/rules/camelcase) docs quoted below:
> It ignores leading and trailing underscores and only checks those in the middle of a variable name.

**What actually happened? Please include the actual, raw output from ESLint.**
```log
/Users/kyle/tmp/test.js
  2:8  error  Identifier '_value' is not in camel case  camelcase

✖ 1 problem (1 error, 0 warnings)
```
