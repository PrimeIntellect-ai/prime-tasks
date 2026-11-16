Better error handling when YAML translation is unparseable
In the example above, space is missing in line `en:bar`.

```yaml
i18n:
  pl: foo
  en:bar
```

Right now it's pretty hard to narrow down the problem. We should add a better error handling.

### Additional contract requirements

- When a YAML translation cannot be parsed, the compiler reports an error whose `type` is `YAMLTranslationError` and whose `message` is a non-empty description of the parse failure.
- Add public error classes `YAMLTranslationError(message)`, `JSONTranslationError(message)` and `JavaScriptTranslationError(message)` in `src/utilities/errors.js`. Each class is a subclass of `BaseError` and carries the message it is constructed with.
- `YAMLTranslationError` has `type` `YAMLTranslationError`, `JSONTranslationError` has `type` `JSONTranslationError`, and `JavaScriptTranslationError` has `type` `JavaScriptTranslationError`.
- When a JSON translation cannot be parsed, the compiler reports an error whose `type` is `JSONTranslationError` and whose `message` is the underlying JSON parse error description.
