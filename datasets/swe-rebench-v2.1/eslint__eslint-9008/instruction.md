upgrade 3.19 to 4.3.0 - no-multi-spaces -  incredibly slow
```
Rule                     |  Time (ms) | Relative
:------------------------|-----------:|--------:
no-multi-spaces          | 128895.239 |    98.8%
indent                   |    572.412 |     0.4%
comma-style              |     87.177 |     0.1%
comma-spacing            |     62.077 |     0.0%
no-regex-spaces          |     51.506 |     0.0%
keyword-spacing          |     50.365 |     0.0%
mocha/no-identical-title |     47.103 |     0.0%
no-control-regex         |     42.972 |     0.0%
key-spacing              |     41.282 |     0.0%
no-useless-escape        |     38.029 |     0.0%
```
**Tell us about your environment**

* ESLint Version:*4.3*
* Node Version:*8.1.4*
* npm Version:*5.3.0*

**What parser (default, Babel-ESLint, etc.) are you using?**

**Please show your full configuration:**
```json
{
  "root": true,
  "extends": "eslint:recommended",

  "rules": {

    "curly": ["error", "all"],
    "eqeqeq": "error",
    "no-eq-null": "error",
    "vars-on-top": "error",
    "wrap-iife": ["error", "any"],
    "max-params": ["warn", { "max": 5 }],
    "no-console": "error",
    "no-unused-vars": ["error", {
      "vars": "all",
      "args": "none"
    }],
    "semi": ["error", "always"],


    // Structure

    "block-spacing": ["warn", "always"],
    "brace-style": ["warn", "1tbs", { "allowSingleLine": true }],
    "comma-dangle": ["warn", "only-multiline"],
    "comma-spacing": ["warn", { "before": false, "after": true }],
    "comma-style": ["warn", "last"],
    "dot-location": ["warn", "property"],
    "indent": ["warn", "tab"],
    "key-spacing": ["warn", {
      "beforeColon": false,
      "afterColon": true,
      "mode": "minimum"
    }],
    "keyword-spacing": ["warn", { "before": true, "after": true }],
    "linebreak-style": ["warn", "unix"],
    "quotes": ["warn", "double", "avoid-escape"],
    "space-infix-ops": "warn",
    "space-unary-ops": ["warn", { "words": true, "nonwords": false }],


    // Other whitespace

    "eol-last": ["warn", "unix"],
    "newline-after-var": ["warn", "always"],
    "newline-before-return": "warn",
    "no-mixed-spaces-and-tabs": ["warn", "smart-tabs"],
    "no-multiple-empty-lines": ["warn", { "max": 2 }],
    "no-multi-spaces": ["warn"],
    "no-trailing-spaces": ["warn", { "skipBlankLines": true }],
    "padded-blocks": [0, "never"],
    "space-before-blocks": ["warn", "always"],
    "space-before-function-paren": ["warn", { "anonymous": "always", "named": "never" }],
    "space-in-parens": ["warn", "never"],
    "spaced-comment": ["warn", "always"],


    // Misc

    "valid-jsdoc": ["warn", {
      "prefer": {
        "return": "returns"
      },
      "requireReturn": false,
      "requireReturnDescription": false
    }],

	"mocha/no-exclusive-tests": "error",
	"mocha/no-identical-title": "error"
  },

  "parserOptions": {
	"ecmaVersion": 8,
	"sourceType": "module",
	"ecmaFeatures": {
	  "experimentalObjectRestSpread": true
	}
  },

  "env": {
    "node": true
  },

  "globals" : {
    "Promise": true
  },

  "plugins": [
	"mocha"
  ]
}
```
<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js



```

</details>

**What did you do? Please include the actual source code causing the issue.**

<!-- Paste the source code below: -->
```js
eslint src test
```

**What did you expect to happen?**

As with eslint 3.19 completing within few seconds

**What actually happened? Please include the actual, raw output from ESLint.**
