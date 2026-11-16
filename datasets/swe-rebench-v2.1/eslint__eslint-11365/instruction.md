Rule ´prefer-spread´ breaks ´Array.apply´ code
**Tell us about your environment**

* **ESLint Version:** 5.12.1
* **Node Version:** 10.15.0
* **npm Version:** 6.5.0

**What parser (default, Babel-ESLint, etc.) are you using?** `babel-eslint` v. 10.0.1

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
# `package.json`
```json
{
  "devDependencies": {
    "@babel/cli": "^7.2.3",
    "@babel/core": "^7.2.2",
    "@babel/plugin-proposal-class-properties": "^7.2.3",
    "@babel/plugin-proposal-decorators": "^7.2.3",
    "@babel/plugin-proposal-do-expressions": "^7.2.0",
    "@babel/plugin-proposal-export-default-from": "^7.2.0",
    "@babel/plugin-proposal-export-namespace-from": "^7.2.0",
    "@babel/plugin-proposal-function-bind": "^7.2.0",
    "@babel/plugin-proposal-function-sent": "^7.2.0",
    "@babel/plugin-proposal-json-strings": "^7.2.0",
    "@babel/plugin-proposal-logical-assignment-operators": "^7.2.0",
    "@babel/plugin-proposal-nullish-coalescing-operator": "^7.2.0",
    "@babel/plugin-proposal-numeric-separator": "^7.2.0",
    "@babel/plugin-proposal-optional-chaining": "^7.2.0",
    "@babel/plugin-proposal-pipeline-operator": "^7.2.0",
    "@babel/plugin-proposal-throw-expressions": "^7.2.0",
    "@babel/plugin-syntax-dynamic-import": "^7.2.0",
    "@babel/plugin-syntax-import-meta": "^7.2.0",
    "@babel/polyfill": "^7.2.5",
    "@babel/preset-env": "^7.2.3",
    "@babel/preset-react": "^7.0.0",
    "@babel/runtime": "^7.2.0",
    "babel-eslint": "^10.0.1",
    "babel-loader": "^8.0.0",
    "babel-plugin-transform-es2015-modules-commonjs": "^6.26.2",
    "eslint": "^5.11.1",
    "eslint-config-airbnb": "^17.1.0",
    "eslint-plugin-import": "^2.14.0",
    "eslint-plugin-jsx-a11y": "^6.1.2",
    "eslint-plugin-react": "^7.11.1",
    "file-loader": "^2.0.0",
    "html-webpack-plugin": "^3.2.0",
    "json-loader": "^0.5.7",
    "node-sass": "^4.11.0",
    "postcss-loader": "^3.0.0",
    "sass-loader": "^7.1.0",
    "svg-url-loader": "^2.3.2",
    "uglifyjs-webpack-plugin": "^2.1.0",
    "webpack": "^4.28.2",
    "webpack-cli": "^3.1.2",
    "webpack-dev-server": "^3.1.14"
  }
}
```

# `.eslintrc`
```json
{
  "parser": "babel-eslint",
  "extends": "airbnb",
  "rules": {
    "max-len": ["error", 180],
    "semi": [2, "always"],
    "quotes": [2, "single"],
    "indent": [1, "tab", {
      "SwitchCase": 1
    }],
    "react/jsx-indent": [1, "tab"],
    "react/jsx-one-expression-per-line": 0,
    "no-tabs": 0,
    "react/react-in-jsx-scope": 0,
    "jsx-quotes": [2, "prefer-single"],
    "react/jsx-curly-spacing": ["error", "always"],
    "react/jsx-indent-props": [2, "tab"],
    "comma-dangle": [1, "always-multiline"],
    "no-console": 0,
    "no-underscore-dangle": 0,
    "react/prefer-stateless-function": 0,
    "padded-blocks": 0,
    "no-script-url": 0,
    "react/forbid-prop-types": 0,
    "react/require-default-props": 0,
    "arrow-parens": [2, "as-needed"],
    "no-return-assign": 0,
    "react/sort-comp": 0,
    "linebreak-style": 0,
    "template-curly-spacing": ["error", "always"],
    "no-trailing-spaces": ["error", {
      "skipBlankLines": true
    }],
    "no-confusing-arrow": 0,
    "jsx-a11y/no-static-element-interactions": 0,
    "import/prefer-default-export": 0,
    "no-nested-ternary": 0,
    "jsx-a11y/anchor-is-valid": 0,
    "object-curly-newline": 0,
    "space-before-function-paren": [1, "always"],
    "react/jsx-tag-spacing": [0, "never"]
  },
  "globals": {
    "_": true,
    "log": true
  },
  "env": {
    "browser": true,
    "es6": true,
    "node": true,
    "jest": true
  },
  "settings": {
    "import/resolver": {
      "node": {
        "moduleDirectory": [
          "node_modules",
          "src"
        ]
      }
    }
  }
}

```


</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
// `index.js`
Array.apply(null, { length: 10 }).map((e, i) => ++i); // [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ]
```

<!-- Paste the command you used to run ESLint: -->
```bash
eslint --fix index.js
```

**What did you expect to happen?**
No changes

**What actually happened? Please include the actual, raw output from ESLint.**
```js
// `index.js` becomes
Array(...{ length: 10 }).map((e, i) => ++i); // TypeError: ({length:10}) is not iterable
```

**Are you willing to submit a pull request to fix this bug?**
Maybe.

### Additional contract requirements

- With the `prefer-spread` rule enabled, running ESLint with `--fix` on `Array.apply(null, { length: 10 });` must leave the source unchanged. The array-like argument must not be rewritten as a spread argument.
