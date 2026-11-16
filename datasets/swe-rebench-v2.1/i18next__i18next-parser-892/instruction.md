Keys extracted with escaped characters starting in v8.4.0
## 🐛 Bug Report

Up to v8.3.0, the following code would result in the key being extracted as `"Don't click me"`:

```js
<Trans shouldUnescape>Don&apos;t click me</Trans>
```

Starting in v8.4.0, it gets extracted as `"Don&apos;t click me"`. The main reason this is an issue is that i18next will look for the key as "Don't click me", disregarding of whether `shouldUnescape` is `true` or `false` (I reported that as a separate issue [here](https://github.com/i18next/react-i18next/issues/1662)).

This basically means that all the keys extracted by i18next-parser which contained escaped characters will be ignored by i18next.

## Your Environment

- *runtime version*: node v18
- *i18next version*: 23.4.4
- *react-i18next*: 13.1.2
- *os*: MacOs
