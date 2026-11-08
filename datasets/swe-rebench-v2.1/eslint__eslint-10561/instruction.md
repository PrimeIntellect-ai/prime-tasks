Error when nesting an unknown logical operator
**Tell us about your environment**

* **ESLint Version:** 5.0.0
* **Node Version:** 9.11.2

**What parser (default, Babel-ESLint, etc.) are you using?** babel-eslint@9.0.0-beta.1

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
{
  "parser": "babel-eslint",
  "rules": {
    "strict": 0
  }
}
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
foo && bar ?? baz
```

<!-- Paste the command you used to run ESLint: -->
```bash
node_modules/.bin/eslint my-file.js
```

**What did you expect to happen?**

No errors

**What actually happened? Please include the actual, raw output from ESLint.**

```
TypeError: Cannot read property 'trueForkContext' of null
    at CodePathState.popChoiceContext (<some-path>/node_modules/eslint/lib/code-path-analysis/code-path-state.js:403:35)
    at processCodePathToExit (<some-path>/node_modules/eslint/lib/code-path-analysis/code-path-analyzer.js:457:23)
    at CodePathAnalyzer.leaveNode (<some-path>/node_modules/eslint/lib/code-path-analysis/code-path-analyzer.js:653:9)
    at nodeQueue.forEach.traversalInfo (<some-path>/node_modules/eslint/lib/linter.js:863:28)
```
