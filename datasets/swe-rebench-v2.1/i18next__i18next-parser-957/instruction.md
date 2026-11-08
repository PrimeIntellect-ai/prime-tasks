Regression with version 8.0.11
## 🐛 Bug Report

After upgrade to 8.0.11, this command fail:
```
i18next 'src/**/*.{ts,tsx}' --config i18next-parser.config.js --fail-on-update --silent
```

With

```
> i18next 'src/**/*.{ts,tsx}' --config i18next-parser.config.js --fail-on-update --silent

  [error]   Some keys were sorted and failOnUpdate option is enabled. Exiting...
npm ERR! Lifecycle script `i18n:check` failed with error:
npm ERR! Error: command failed
```

Sort is enabled.

If I remove `--fail-on-update`, no file are updated, so no need to sort anything.

## To Reproduce

Run the command above with this config file:

```javascript

module.exports = {
  contextSeparator: '_',
  createOldCatalogs: false,
  defaultNamespace: 'translation',
  defaultValue: '',
  indentation: 2,
  keepRemoved: false,
  keySeparator: '.',
  lexers: {
    hbs: ['HandlebarsLexer'],
    handlebars: ['HandlebarsLexer'],

    htm: ['HTMLLexer'],
    html: ['HTMLLexer'],

    mjs: ['JavascriptLexer'],
    ts: ['JsxLexer'],
    jsx: ['JsxLexer'],
    tsx: ['JsxLexer'],

    default: ['JavascriptLexer'],
  },
  lineEnding: 'lf',
  locales: ['en', 'fr'],
  namespaceSeparator: ':',
  output: 'src/locales/$LOCALE/$NAMESPACE.json',
  pluralSeparator: '_',
  input: undefined,
  sort: true,
  skipDefaultValues: false,
  useKeysAsDefaultValue: false,
  verbose: false,
  failOnWarnings: false,
  failOnUpdate: false,
  customValueTemplate: null,
  resetDefaultValueLocale: null,
  i18nextOptions: null,
};
```

## Expected behavior

No file need to be sorted so I should not have any error.

## Your Environment

- *runtime version*: node v21.5.0
- *i18next version*: 23.7.12
- *i18next-parser version*: 8.11.0
- *os*: Mac
