Conditional `useKeysAsDefaultValue`
## 🚀 Feature Proposal

I would like to enable `useKeysAsDefaultValue` conditionally based on the generated locale.

## Motivation

I use natural keys, so for the source language (English, in my case), I would like to generate files where the key is set to the default value. However, for all other languages, I would like to generate empty values so it's clear which parts still have to be translated.

## Example

```js
skipDefaultValues: true,
useKeysAsDefaultValue: (locale) => locale === defaultLocale ? true : false
```

---

I'd be happy to send a PR for this if it's something you are willing to add :)
