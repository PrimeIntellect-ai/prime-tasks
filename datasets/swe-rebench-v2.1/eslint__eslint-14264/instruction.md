no-unused-vars with ignoreRestSiblings:true reports false-positives
<!--
    ESLint adheres to the Open JS Foundation Code of Conduct:
    https://eslint.org/conduct

    This template is for bug reports. If you are here for another reason, please see below:

    1. To propose a new rule: https://eslint.org/docs/developer-guide/contributing/new-rules
    2. To request a rule change: https://eslint.org/docs/developer-guide/contributing/rule-changes
    3. To request a change that is not a bug fix, rule change, or new rule: https://eslint.org/docs/developer-guide/contributing/changes
    4. If you have any questions, please stop by our chatroom: https://eslint.org/chat/help

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->


**Tell us about your environment**

<!--
    If you are using ESLint v6.5.0 or later, you can run ESLint with the `--env-info` flag and paste the output here.
-->

* **ESLint Version:** 7.21.0
* **Node Version:** 12.16.2
* **npm Version:** 6.14.4
* **Operating System:** Windows

**What parser (default, `@babel/eslint-parser`, `@typescript-eslint/parser`, etc.) are you using?**
babel-eslint

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
module.exports = {
    extends: 'airbnb',
    parser: 'babel-eslint',
    plugins: [
        'jasmine',
        'webdriverio',
        'react-redux',
    ],
    env: {
        'browser': true,
        'node': true,
        'jasmine': true,
        'webdriverio/wdio': true,
    },
    rules: {
        'import/no-cycle': 'off',
        'react/jsx-props-no-spreading': 'off',
        'react/no-access-state-in-setstate': 'off',
        'arrow-parens': ['error', "as-needed", { "requireForBlockBody": true }],
        'function-paren-newline': 'off',
        'indent': ['error', 4, { 'SwitchCase': 1 }],
        'no-undef': 'error',
        'no-underscore-dangle': 'off',
        'no-multiple-empty-lines': ['warn', { "max": 2 } ],
        'no-else-return': ['error', { allowElseIf: true }],
        'no-restricted-globals': [
            "error",
            { name: 'Set', message: 'Use window.Set or add an eslint-ignore if native Set is what you want' },
            { name: 'Map', message: 'Use window.Map or add an eslint-ignore if native Map is what you want' }
        ],
        'max-len': ['error', 120],
        'implicit-arrow-linebreak': 'off',
        'jsx-a11y/click-events-have-key-events': 'off',
        'jsx-a11y/interactive-supports-focus': 'off',
        'jsx-a11y/label-has-for': 'off',
        'jsx-a11y/label-has-associated-control': 'off',
        'jsx-a11y/no-noninteractive-element-interactions': 'off',
        'jsx-a11y/no-static-element-interactions': 'off',
        'jsx-a11y/anchor-is-valid': 'off',
        'jsx-a11y/control-has-associated-label': 'off',
        'class-methods-use-this': 'off',
        'no-plusplus': ['error', { 'allowForLoopAfterthoughts': true }],
        'no-mixed-operators': ['error', { 'allowSamePrecedence': true }],
        'no-multi-spaces': ['error', { ignoreEOLComments: true }],
        'no-console': 'warn',
        'no-continue': 'off',
        'no-unused-vars': ['error', { 'ignoreRestSiblings': true }],
        'object-curly-newline': 'off',
        'operator-linebreak': ["warn", "after"],
        'prefer-destructuring': 'off',
        'prefer-promise-reject-errors': 'warn',
        'react/sort-comp': ['warn', { order: ['static-methods',  'lifecycle', 'everything-else', 'render'] }],
        'react/forbid-prop-types': 'off',
        'react/jsx-fragments': 'off',
        'react/jsx-filename-extension': 'off',
        'react/jsx-indent': ['error', 4],
        'react/jsx-indent-props': ['error', 4],
        'react/no-danger': 'off',
        'react/require-default-props': 'off',
        'react/jsx-boolean-value': 'off',
        'react/no-did-update-set-state': 'off', // recommended way since 16.3.
        'react/destructuring-assignment': 'off',
        'react/static-property-placement': 'off',
        'react-redux/prefer-separate-component-file': 'off',
        'react-redux/connect-prefer-named-arguments': 'off',
        'react/no-unused-prop-types': 'off', // superseded by react-redux/no-unused-prop-types
        'react/jsx-props-no-multi-spaces': 'off',
        // disallow certain syntax forms
        // http://eslint.org/docs/rules/no-restricted-syntax
        'no-restricted-syntax': [
            'error',
            {
                selector: 'ForInStatement',
                message: 'for..in loops iterate over the entire prototype chain, which is virtually never what you want. Use Object.{keys,values,entries}, and iterate over the resulting array.',
            },
            {
                selector: 'LabeledStatement',
                message: 'Labels are a form of GOTO; using them makes code confusing and hard to maintain and understand.',
            },
            {
                selector: 'WithStatement',
                message: '`with` is disallowed in strict mode because it makes code impossible to predict and optimize.',
            },
        ],
        camelcase: 'off'
    },
    globals: {
        '__BUILD_NR__': true,
        'requestIdleCallback': true,
        'any': true
    },
    settings: {
        'import/core-modules': [
            'native-api',
        ],
        'react': {
            'pragma': 'React',
            'version': '16.3'
        },
    }
};

```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```
function buildLibraryStructure(folders, entries) {
    const structureMap = {
        root: {
            id: 'root',
            title: 'Library',
            type: navItemTypes.folder,
            parent: null,
            children: [],
            weight: 1,
        },
    };

    // reused dummy variables used to spread data out of entries/folders
    /* eslint-disable no-unused-vars */
    let folder;
    let validFrom;
    let validUntil;
    let parent;
    /* eslint-enable no-unused-vars */
    let rest;

    // Add folders to map of items
    folders.forEach((folderItem) => {
        ({ folder, validFrom, validUntil, ...rest } = folderItem);

        structureMap[folderItem.id] = {
            ...rest,
            oid: folderItem.id,
            isFolder: true,
        };
    });
    return structureMap;
}
```

**What did you expect to happen?**
I believe the rule `no-unused-vars` should not be triggered.

The rule is configured as `'no-unused-vars': ['error', { 'ignoreRestSiblings': true }],`.
The above code splits definition and spreading of the two variables `folder` and `rest`. The definition of the variables are even enclosed in a `disable no-unused-vars`

**What actually happened? Please copy-paste the actual, raw output from ESLint.**

>   38:16  error  'folder' is assigned a value but never used      no-unused-vars
>   38:20  error  'validFrom' is assigned a value but never used   no-unused-vars
>   38:31  error  'validUntil' is assigned a value but never used  no-unused-vars

**Steps to reproduce this issue:**

<!-- Please tell us exactly how to see the issue you're describing -->

1. split definition and usage of variables
1. use the rest operator with a throw-away variables on an other line
1. no-unsed-vars is triggered

**Are you willing to submit a pull request to fix this bug?**
No, I don't think I could
