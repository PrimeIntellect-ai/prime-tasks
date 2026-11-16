Trans defaults cause variable names to be treated as keys
<!--
Before you submit an issue we recommend you visit [docs](https://www.i18next.com/) or [docs](https://react.i18next.com/) or [StackOverflow](https://stackoverflow.com/) or similar and ask any questions you have or mention any problems you've had getting started with i18next.

**Please read this entire template before posting any issue. If you ignore these instructions and post an issue here that does not follow the instructions, your issue might be closed, locked.**
-->

## 🐛 Bug Report

The Trans component can be used to interpolate a line with i18next-react templates ("...<1>..."), but not to translate keys (what the `t()` function does). Although I am aware that the Trans component can also perform key translation, there are cases where this is not desired.

In this case, parsing mistakenly extracts a key when nothing should be extracted.
This is a regression that I discovered when upgrading from 3.0.1 to 3.3.0.

## To Reproduce

```js
const line = 'some generated template with <1>bold</1> text';

function Repro() {
  return (
    <Trans
      defaults={line}
      components={[<bold>text</bold>]}
    />
  );
}
```

Parsing should generate an empty file, but produces the following file:
```
{ "line": "line" }
```

## Your Environment

- *runtime version*: i.e. node v13
- *i18next-parser*: 3.3.0
- *i18next*: 19.8.3
- *react-i18next*: 11.7.3
- *os*: Linux

### Additional contract requirements

- For `<Trans defaults="Steve">{{ name }}</Trans>`, extraction must return exactly `[{ key: '{{name}}', defaultValue: 'Steve' }]`.
