`max-len` `ignoreStrings` does not ignore jsx prop strings
**Tell us about your environment**

* **ESLint Version:** v4.16.0
* **Node Version:** v8.9.1
* **npm Version:** v5.6.0

**What parser (default, Babel-ESLint, etc.) are you using?**
default

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```json
{
  "rules": {
    "max-len": [2, { "code": 5", "ignoreStrings": true }],
  },
}
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
<input placeholder="something long" />
```

<!-- Paste the command you used to run ESLint: -->
```bash
eslint foo.js
```

**What did you expect to happen?**
No error.

**What actually happened? Please include the actual, raw output from ESLint.**
 1:1  error  Line 1 exceeds the maximum line length of 5  max-len
