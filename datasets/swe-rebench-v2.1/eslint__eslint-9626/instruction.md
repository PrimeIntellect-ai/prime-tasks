prefer-destructuring says "Use destructuring" on "super"
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for bug reports. If you are reporting a bug, please continue on. If you are here for another reason, please see below:

    1. To propose a new rule: https://eslint.org/docs/developer-guide/contributing/new-rules
    2. To request a change: https://eslint.org/docs/developer-guide/contributing/changes
    3. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**

* **ESLint Version: 4.11.0**
* **Node Version: v9.2.0**
* **npm Version: 5.5.1**

**What parser (default, Babel-ESLint, etc.) are you using?**
default

**Please show your full configuration:**
<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
const config = {
    parserOptions: {
        ecmaVersion: 6,
    },
    rules: {
        'prefer-destructuring': ['warn'],
    },
};
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
// eslint-test.js
const code = `
class Node {
    static get inheritance() {
        return ['node'];
    }
}
class Element extends Node {
    static get inheritance() {
        const inheritance = super.inheritance;
        inheritance.push('element');
        return inheritance;
    }
}
console.log(Element.inheritance);
`;
const {Linter} = require('eslint');
const linter = new Linter();
const config = {
    parserOptions: {
        ecmaVersion: 6,
    },
    rules: {
        'prefer-destructuring': ['warn'],
    },
};
const messages = linter.verify(code, config);
for (const message of messages) {
    console.log(message);
}
```

<!-- Paste the command you used to run ESLint: -->
```bash
node ./eslint-test.js
```

**What did you expect to happen?**
I expect `prefer-destructuring` ignores the `const inheritance = super.inheritance;` statement.
`const {inheritance} = super` throws a SyntaxError.

**What actually happened? Please include the actual, raw output from ESLint.**
```
{ ruleId: 'prefer-destructuring',
  severity: 1,
  message: 'Use object destructuring.',
  line: 9,
  column: 15,
  nodeType: 'VariableDeclarator',
  source: '        const inheritance = super.inheritance;',
  endLine: 9,
  endColumn: 40 }
```
