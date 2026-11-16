JS Lexer does not recognize keys in the options passed to `t` func
## 🐛 Bug Report
When using the built-in Javascript Lexer, `t` wrapped keys in the options that are passed to the `t` function are ignored and not parsed.
E.g. `t('foo {{ target }}', { target: t('bar') })`
- `foo {{ target }}` is extracted
- `bar` is not`

## To Reproduce
Run i18next-parser with the base JS lexer on any .js file containing the following line:
```js
 // t('foo {{ target }}', { target: t('bar') })
```

## Expected behavior

Translated keys within the options passed to already extracted keys should be caught as well.

```json
{
 "foo {{ target }}": "foo {{ target }}",
 "bar": "bar"
}
```

## Your Environment

- *runtime version*: node v14 and node v18
- *i18next-parser*: 7.0.0
- *i18next*: 21.5.2
- *os*: Windows

Apologies if this has been reported before. We'd like to avoid extra comments and lines if possible and the included JS lexer does not appear to catch the below case. Assistance or a reference to what is considered best practices in this situation would be appreciated.
