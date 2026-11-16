Adding ignore-path flag referencing a file in node_modules not respecting ignore config
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for bug reports. If you are reporting a bug, please continue on. If you are here for another reason, please see below:

    1. To propose a new rule: http://eslint.org/docs/developer-guide/contributing/new-rules
    2. To request a change: http://eslint.org/docs/developer-guide/contributing/changes
    3. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**

* **ESLint Version:** 4.6.1 (latest)
* **Node Version:** 8.4.0 (latest)
* **npm Version:** 5.4.0 (latest)

**What parser (default, Babel-ESLint, etc.) are you using?** N/A

**Please show your full configuration:** N/A

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
{}
```

</details>

**What did you do? Please include the actual source code causing the issue.**

<!-- Paste the source code below: -->
```
eslint --ignore-path node_modules/kcd-scripts/dist/config/eslintignore .
```

**What did you expect to happen?**

I expected the eslintignore to be applied

**What actually happened? Please include the actual, raw output from ESLint.**

It is not. I get an error indicating that eslint is processing files in `node_modules`.

Here's the contents of `node_modules/kcd-scripts/dist/config/eslintignore`:

```
node_modules
coverage
dist
build
out
.next
```

I think that the docs indicate that the patterns here will be relative to the `.eslintignore` file, so I changed the eslintignore file to various patterns (including `../../../node_modules/`, `**/node_modules/**`). None of those combinations seemed to work. I think there may be a bug here, but I'm uncertain... Happy to dig in more if someone can tell me I'm not missing something obvious.

To reproduce: https://github.com/kentcdodds/eslint-config-issue

Install deps and run `npm run broken` and `npm run working`.

Thanks!

### Additional contract requirements

- When an ignore file is supplied with `--ignore-path`, a pattern beginning with `/` in that file is anchored to the directory that contains the ignore file, so `/undef.js` in `subdir/.eslintignoreInChildDir` ignores `subdir/undef.js` but not `undef.js` in the working directory.
- Default ignore patterns such as `/node_modules` remain anchored to the current working directory, even when the supplied ignore file lives in a different directory.
