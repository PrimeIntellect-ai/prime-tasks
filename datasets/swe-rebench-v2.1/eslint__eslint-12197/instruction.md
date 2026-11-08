Fix range bug with no-extra-boolean-cast
**Tell us about your environment**

* **ESLint Version:** 5.12.1
* **Node Version:** 8.11.4
* **npm Version:** 5.6.0

**What parser (default, Babel-ESLint, etc.) are you using?** default

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```json
{
  "extends": ["eslint:recommended"],
  "rules": {
    "no-extra-boolean-cast": "error"
  }
}
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
var bar = 1;
var foo = !!bar ? 'true' : 'false';
```

<!-- Paste the command you used to run ESLint: -->
```bash
npm run lint -- --format=json
```

**What did you expect to happen?**
The information about the location of the fix appears to be off. Running `--fix` applies the fix correctly but the response from the JSON output is off (which means that other external tools cannot apply the fix).

I would expect the location information to be something like:
```json
{
  "line": 2,
  "column": 11,
  "nodeType": "UnaryExpression",
  "messageId": "unexpectedNegation",
  "endLine": 2,
  "endColumn": 16,
  "fix": { "range": [24, 29], "text": "bar" }
}
```

Looking at AST Explorer seems to have the right location information.

https://astexplorer.net/#/gist/b5517bff697af4446176699497517e36/8f1a35f7594886e63d855960a1649120071963d4
**What actually happened? Please include the actual, raw output from ESLint.**
```json
[
  {
    "filePath": "/Volumes/Freelancer/scratch/eslint/test.js",
    "messages": [
      {
        "ruleId": "no-unused-vars",
        "severity": 2,
        "message": "'foo' is assigned a value but never used.",
        "line": 2,
        "column": 5,
        "nodeType": "Identifier",
        "endLine": 2,
        "endColumn": 8
      },
      {
        "ruleId": "no-extra-boolean-cast",
        "severity": 2,
        "message": "Redundant double negation.",
        "line": 2,
        "column": 12,
        "nodeType": "UnaryExpression",
        "messageId": "unexpectedNegation",
        "endLine": 2,
        "endColumn": 16,
        "fix": { "range": [23, 28], "text": "bar" }
      }
    ],
    "errorCount": 2,
    "warningCount": 0,
    "fixableErrorCount": 1,
    "fixableWarningCount": 0,
    "source": "var bar = 1;\nvar foo = !!bar ? 'true' : 'false';\n"
  }
]
```

**Are you willing to submit a pull request to fix this bug?** With help potentially. I'm unfamiliar with how rules output the position information.
