Debug command returns undefined for package versions
Seen on recent issues.

Example:


<details>

```
Atom version: 1.18.0
prettier-atom version: undefined
prettier version: undefined
prettier-eslint version: undefined
prettier-atom configuration: {
  "formatOnSaveOptions": {
    "enabled": true,
    "respectEslintignore": true,
    "showInStatusBar": false,
    "javascriptScopes": [
      "source.js",
      "source.jsx",
      "source.js.jsx",
      "source.babel",
      "source.js-semantic",
      "text.html.basic",
      "text.html.vue"
    ],
    "typescriptScopes": [
      "source.ts",
      "source.tsx",
      "source.ts.tsx"
    ],
    "cssScopes": [
      "source.css",
      "source.less",
      "source.css.less",
      "source.scss",
      "source.css.scss"
    ],
    "excludedGlobs": [],
    "whitelistedGlobs": [],
    "isDisabledIfNotInPackageJson": false
  },
  "prettierEslintOptions": {
    "prettierLast": false
  },
  "prettierOptions": {
    "semi": false,
    "singleQuote": true,
    "bracketSpacing": true,
    "useTabs": false,
    "jsxBracketSameLine": false,
    "printWidth": 80,
    "tabWidth": "auto",
    "trailingComma": "none",
    "parser": "babylon"
  },
  "useEslint": true,
  "silenceErrors": false,
  "useEditorConfig": true
}
```
</details>
