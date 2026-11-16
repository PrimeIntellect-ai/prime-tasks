Using editor preferences
Updating to `prettier-atom@0.50.0` I've noticed my editor preference for single quotes isn't being respected. It's formatting everything to be double quotes.

I'm only using `prettier`, and have the `eslint` integration disabled. I do have an eslint config, but that also is set to use single quotes.

I'm guessing this may be a result of #374?

```
Atom version: 1.23.3
prettier-atom version: 0.50.0
prettier version: 1.10.2
prettier-eslint version: 8.8.1
prettier-atom configuration: {
  "formatOnSaveOptions": {
    "enabled": true,
    "excludedGlobs": [
      "package.json"
    ],
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
      "source.css.scss",
      "source.css.postcss"
    ],
    "jsonScopes": [
      "source.json"
    ],
    "graphQlScopes": [
      "source.graphql"
    ],
    "markdownScopes": [
      "source.md",
      "source.gfm",
      "text.md"
    ],
    "vueScopes": [
      "text.html.vue"
    ],
    "whitelistedGlobs": [],
    "isDisabledIfNotInPackageJson": false,
    "isDisabledIfNoConfigFile": false
  },
  "prettierOptions": {
    "arrowParens": "always",
    "singleQuote": true,
    "trailingComma": "all",
    "bracketSpacing": true,
    "semi": true,
    "useTabs": false,
    "jsxBracketSameLine": false,
    "printWidth": 80,
    "tabWidth": "auto",
    "parser": "babylon"
  },
  "silenceErrors": false,
  "useEslint": false,
  "useStylelint": false,
  "useEditorConfig": true,
  "prettierEslintOptions": {
    "prettierLast": false
  }
}
```

### Additional contract requirements

When ESLint integration is disabled and the editor's Prettier option `singleQuote` is true, formatting uses single quotes.
