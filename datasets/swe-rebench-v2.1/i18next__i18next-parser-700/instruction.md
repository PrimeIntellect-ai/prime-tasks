Add a config to keep some dynamic keys
## 🚀 Feature Proposal

Add an option so that `i18next-parser` keeps some of the keys that are in the translation files but are not extracted from the code.

## Motivation

When using dynamic keys or dynamic contexts, there are multiple reasons for adding some keys that would be used at runtime while not easy to extract from the code statically. I'd like to be able to use `i18next-parser` to get all the other keys right, but trust me on the keys that I've added myself to the translation files.

As of v7, I only have the choice to either keep all existing translations (`keepRemoved` option) or delete all the ones that `i18next-parser` cannot extract from the code. I'd like to have another option and list patterns for which I want to keep the translations that exist.

## Example

Given the following code (using React):
```tsx
  const {t} = useTranslation()
  return <p>
    {t('pickACountryQuestion')}
    <select>
     {countries.map(countryId => <option value={countryId}>{t(`countryName.${countryId}`)}</option>)}
    </select>
  </p>
```

Adding this in the `i18next-parser.config.js`:
```js
module.exports = {
  keepRemovedPatterns: [
    /^translation:countryName\.\w+/,
  ]
}
```

I'd like to keep all the `countryName` sub tree containing something like:
```json
  "countryName": {

    "BDI": "Burundi",
    "BEL": "Belgium",
    "BEN": "Benin",

  }
```
while still removing other keys not used in my code.

### Additional contract requirements

The public configuration option is named `keepRemoved`. It accepts either a boolean or an array of RegExp patterns. When it is an array, a removed key is kept in the catalog if its full dot-separated path (including the namespace prefix and the configured separators) matches any of the patterns; removed keys that match no pattern are dropped. The example above shows the option under the name `keepRemovedPatterns`; the implemented and tested public option name is `keepRemoved`.
