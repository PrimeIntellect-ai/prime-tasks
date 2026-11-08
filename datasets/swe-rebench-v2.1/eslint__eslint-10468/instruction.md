no-unneeded-ternary --fix breaks with yield statement
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

* **ESLint Version:** v4.19.1
* **Node Version:** v9.6.1
* **npm Version:** 5.6.0

**What parser (default, Babel-ESLint, etc.) are you using?**

babel-eslint

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
{
  "extends": [
    "airbnb-base",
    "plugin:flowtype/recommended",
    "plugin:react/recommended"
  ],
  "plugins": [
    "flowtype"
  ],
  "parser": "babel-eslint",
  "parserOptions": {
    "ecmaVersion": 8,
    "sourceType": "module",
    "ecmaFeatures": {
      "experimentalObjectRestSpread": true,
      "modules": true,
      "jsx": true,
      "impliedStrict": true
    }
  },
  "globals": {
    "jest": false,
    "expect": false,
    "__DEV__": false
  },
  "env": {
    "browser": true,
    "node": true,
    "mocha": true,
    "es6": true
  },
  "rules": {
    "max-len": ["error", 100, {
      "ignoreUrls": true,
      "ignoreStrings": true,
      "ignoreTemplateLiterals": true,
      "ignoreRegExpLiterals": true
    }],
    "linebreak-style": ["error", "unix"],
    "quotes": ["error", "single", { "avoidEscape": true }],
    "no-param-reassign": "off",
    "camelcase": "off",
    "no-underscore-dangle": "off",
    "space-before-function-paren": ["error", "always"],
    "func-style": ["error", "expression", { "allowArrowFunctions": true }],
    "func-names": ["error", "as-needed"],
    "import/no-extraneous-dependencies": ["error", {"devDependencies": ["**/*.test.js",  "test/*.js"]}],
    "flowtype/delimiter-dangle": 2,
    "flowtype/require-return-type": 2,
    "flowtype/require-parameter-type": 2
  },
  "settings": {
    "flowtype": {
      "onlyFilesWithFlowAnnotation": true
    },
    "import/resolver": {
      "babel-module": {}
    }
  }
}
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
const exampleFunc = function* (in) {
  const result = in ? in : yield 1;
};
```

<!-- Paste the command you used to run ESLint: -->
```bash
 ./node_modules/.bin/eslint --fix
```

**What did you expect to happen?**

ESLint should return:

```js
const exampleFunc = function* (in) {
  const result = in || (yield 1);
};
```

**What actually happened? Please include the actual, raw output from ESLint.**

The issue is that the parser returns invalid syntax with the `--fix` command.

ESLint returns:

```js
const exampleFunc = function* (in) {
  const result = in || yield 1;
};
```

which is invalid JavaScript code.
