arrow-parens ("as-needed") doesn't take async into account
**Tell us about your environment**

* **ESLint Version:** 3.19.0 (with the latest babel-eslint)
* **Node Version:** 7.9.0
* **npm Version:** 4.2.0

**What parser (default, Babel-ESLint, etc.) are you using?** babel-eslint (as eslint doesn't support async

**Please show your full configuration:**

final test with the following, still breaks:
```
{
  "root": true,
  "parser": "babel-eslint",
  "parserOptions": {
    "ecmaVersion": 7,
    "sourceType": "module",
    "ecmaFeatures": {
      "jsx": true,
      "impliedStrict": true,
      "experimentalObjectRestSpread": true
    }
  },
  "env": {
    "browser": true,
    "mocha": true,
    "node": true,
    "es6": true
  },
  "globals": {
    "describe": false,
    "it": false
  },
  "rules": {
    "arrow-parens": [
      2,
      "as-needed"
    ]
  }
}
```

**What did you do? Please include the actual source code causing the issue.**

<!-- Paste the source code below: -->
```js
const foo = async(bar) => {
//...
}

```

**What did you expect to happen?**
fix to
```js
const foo = async bar => {
//...
}```
(or just skip the line, would be fine too)

**What actually happened? Please include the actual, raw output from ESLint.**
```js
const foo = asyncbar => {
//...
}
```

as the async was no longer `async` (but `asyncbar`), causing the function to no longer be an async function
```
/path/to/foo.js
  24:25  error  Parsing error: await is a reserved word
```
