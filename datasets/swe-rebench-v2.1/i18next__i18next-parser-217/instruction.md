How to tell parser to ignore default values in t function?
- Is this a bug or a feature request?

Help question

- What version are you running (`0.x` or `1.x`)?

1.x

- Which runner (cli, gulp...)?

CLI

## What I'm trying to do?

How to tell i18nparser to **not** use the t function default value?

```
t("key", "test")
```

```
t("key", {defaultValue: "test"})
```

results in

en.json
```
{
   key: "test"
}
```

But i want

en.json
```
{
   key: ""
}
```

**Background**: Default values are very useful for developers when working on MVP. Parsing the keys and pushing them to a third party translation service **including** default values, **won't** mark translation keys as "untranslated"!

---

This is my parser config

```
  createOldCatalogs: true,
  defaultNamespace: "common",
  namespaceSeparator: ":",
  defaultValue: "",
  indentation: 2,
  lexers: {
    js: ["JsxLexer"],
    default: ["JsxLexer"],
  },
  lineEnding: "auto",
  locales: locales,
  output: "./public/locales/$LOCALE/$NAMESPACE.json",
  input: ["./**/*.js"],
  reactNamespace: true,
  useKeysAsDefaultValue: false,
  verbose: true,
  keepRemoved: false,
```

### Additional contract requirements

The parser configuration must accept the boolean option `skipDefaultValues`. When it is enabled, defaults passed to `t()` as a string argument or as a `defaultValue` property must be emitted as empty strings in the generated catalog.
