IIFE with leading semicolon wants to be intended when directly after imports
**Tell us about your environment**

* **ESLint Version:** 4.18.2
* **Node Version:** 8.9.3
* **npm Version:** 6.4.1

**What parser (default, Babel-ESLint, etc.) are you using?** default

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
{
    "parserOptions": {
      "ecmaVersion": 2018,
      "ecmaFeatures": {
        "jsx": true
      },
      "sourceType": "module"
    },

    "rules": {
      "indent": ["error", 2]
    }
  }
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
// Imports
import $ from 'jquery'

// Bootstrap
;(() => {
  window.$ = $
})()
```

<!-- Paste the command you used to run ESLint: -->
```bash
node_modules/.bin/eslint -c .eslintrc testFile.js
```

**What did you expect to happen?**
No error, no change of indention needed.

**What actually happened? Please include the actual, raw output from ESLint.**
It wants the `;(() => {` line of the iife with leading semicolon to be indented
```
5:1  error  Expected indentation of 2 spaces but found 0  indent

✖ 1 problem (1 error, 0 warnings)
  1 error, 0 warnings potentially fixable with the `--fix` option.
```

Interestingly if I move this IIFE to below other code, ESLint doesn't try to indent it, only when it's the first bit of code after the import statement.

No errors from:
```js
// Imports
import $ from 'jquery'

function foo (){}

// Bootstrap
;(() => {
  window.$ = $
})()
```


**Are you willing to submit a pull request to fix this bug?**
I'm willing to, but I couldn't easily figure out exactly which part of the indent rule code was causing this
