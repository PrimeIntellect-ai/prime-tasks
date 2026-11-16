Inconsistent evaluation of strings in no-constant-condition
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

* **ESLint Version: 5.9.0**
* **Node Version: 11.3.0**
* **npm Version: 6.4.1**

**What parser are you using?**
babel-eslint

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
{
    "parser": "babel-eslint",
    "parserOptions": {
        "sourceType": "module",
        "allowImportExportEverywhere": true
    },
    "extends": [
        "airbnb",
        "plugin:lodash/recommended"
    ],
    "env": {
        "browser": true,
        "jquery": true,
        "node": true,
        "mocha": true
    },
    "globals": {
        "expect": true,
        "cy": true,
        "Cypress": true,
        "__VERSION__": true,
        "__RELEASED__": true,
        "__INTERCOMID__": true
    },
    "plugins": [
        "backbone",
        "compat",
        "mocha",
        "chai-friendly",
        "lodash",
        "json"
    ],
    "settings": {
        "backbone": {
            "Collection": ["BaseCollection"],
            "Model": ["BaseModel"],
            "View": ["BaseView"]
        }
    },
    "rules": {
        "no-unused-vars": [1, { "vars": "all", "args": "after-used", "ignoreRestSiblings": true, "varsIgnorePattern": "^_", "argsIgnorePattern": "^_" }],
        "no-unused-expressions": 0,
        "chai-friendly/no-unused-expressions": 2,
        "arrow-parens": ["error", "always"],
        "indent": ["error", 4, { "SwitchCase": 1 }],
        "quotes": [1, "double"],
        "comma-dangle": ["error", "never"],
        "new-cap": ["error", { "capIsNew": false }],
        "brace-style": [1, "1tbs", { "allowSingleLine": true }],
        "camelcase": 0,
        "no-plusplus": 0,
        "no-param-reassign": 0,
        "no-underscore-dangle": 0,
        "max-len": 0,
        "no-console": 0,
        "default-case": 0,
        "func-names": 0,
        "no-new": 0,
        "global-require": 0,
        "eol-last": 1,
        "class-methods-use-this": 0,
        "no-cond-assign": [1, "except-parens"],
        "newline-per-chained-call": [2, {"ignoreChainWithDepth": 5}],
        "eqeqeq": ["error", "always"],
        "valid-jsdoc": ["error", { "prefer": { "return": "returns", "extends": "extends" }, "preferType": { "object": "Object" }, "requireReturn": false, "requireReturnType": true, "requireReturnDescription": false, "matchDescription": ".+" }],
        "react/require-extension": [0, { "extensions": [".js"] }],
        "prefer-destructuring": [2, { "array": false, "object": true }, { "enforceForRenamedProperties": false }],
        "import/no-extraneous-dependencies": [0, {}],
        "import/no-unresolved": [2, { "ignore": ["env"] }],
        "import/extensions": 0,
        "import/no-cycle": 0,
        "mocha/no-exclusive-tests": "error",
        "backbone/collection-model": 0,
        "backbone/defaults-on-top": 2,
        "backbone/events-on-top": [2, ["el"]],
        "backbone/initialize-on-top": [2, { "View": ["el", "events"] }],
        "backbone/model-defaults": 0,
        "backbone/no-constructor": 2,
        "backbone/no-el-assign": 2,
        "backbone/no-native-jquery": [2, "selector"],
        "lodash/prefer-lodash-method": 0,
        "lodash/prefer-noop": 1,
        "lodash/import-scope": 0,
        "lodash/prefer-constant": 0,
        "lodash/prefer-filter": 0,
        "lodash/prefer-flat-map": 1,
        "lodash/collection-method-value": 0,
        "lodash/collection-return": 0,
        "lodash/prefer-lodash-chain": 1,
        "lodash/prop-shorthand": 0,
        "lodash/matches-syntax": 0,
        "lodash/matches-shorthand": 0
    }
}
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
if (category === "voucher" || "custom") { }
```

<!-- Paste the command you used to run ESLint: -->
```bash
eslint --fix app
```

**What did you expect to happen?**
An error should be thrown as a string will always evaluate to true. This would be consistent with the following examples where errors are thrown.

```js
if (category === "voucher" || true) { }
```

```js
if ("foo" || "bar") { }
```

**What actually happened? Please include the actual, raw output from ESLint.**
No error was thrown.

**Are you willing to submit a pull request to fix this bug?**
Happy to have a go if somebody can point me in the right direction :)
