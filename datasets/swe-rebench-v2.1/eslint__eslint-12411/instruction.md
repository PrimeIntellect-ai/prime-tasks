keyword-spacing else ghost default
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for bug reports. If you are here for another reason, please see below:

    1. To propose a new rule: https://eslint.org/docs/developer-guide/contributing/new-rules
    2. To request a rule change: https://eslint.org/docs/developer-guide/contributing/rule-changes
    3. To request a change that is not a bug fix, rule change, or new rule: https://eslint.org/docs/developer-guide/contributing/changes
    4. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**

<!--
    If you are using ESLint v6.5.0 or later, you can run ESLint with the `--env-info` flag and paste the output here.
-->

* **ESLint Version:** 6.5.1
* **Node Version:** 10.16.3
* **npm Version:** 6.9.0

**What parser (default, Babel-ESLint, etc.) are you using?**
default
**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```yml
rules: {
  keyword-spacing: ["error", {
    before: false,
    after: true,
    overrides: {
      else: {after: false},
      if: {after: false}
    }
  }],
}
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
if(false) {
  console.info("will not log");
}else{
  console.info("will log");
}
```

<!-- Paste the command you used to run ESLint: -->
```bash
eslint index.js
```

**What did you expect to happen?**
`before: false` should set it so every keyword requires no spacing before it, as no overrides set it to `true`.

**What actually happened? Please include the actual, raw output from ESLint.**
```bash
/path/to/my/file/index.js
  3:2  error  Expected space(s) before "else"  keyword-spacing
```
Although the `before` property appears to work on every other keyword added to the overrides I've tried (`if`, for example, works fine using the above config), `else` for some reason sets it to true. Explicitly setting `before: false` in the `else` override appears to be a temporary solution to this bug.

**Are you willing to submit a pull request to fix this bug?**
I am unsure of how it would be fixed, but I would be willing to submit a PR if I did.

### Additional contract requirements

- When the top-level `before` option is `false` and an `else` override sets only `after`, `else` must not require whitespace before it; the `before` value is taken from the top-level setting.
- An explicit `before: false` inside the `else` override must remain effective: with the top-level `before` set to `true`, `else` must not be preceded by whitespace when the override says `before: false`.
