Extra translations don't override navbar localizations
For an unkown reason, the extra translations don'g override the navbar localizations. In other places e.g. on the catalogue page they work.

- [x] The tab "Aineistoluettelo" should be "Kielivarat". This should come from the key `:t.navigation/catalogue`

### Additional contract requirements

- Extra translations supplied by a theme are merged into the original translations. Values for keys present in both are taken from the extra translations, and the merged result must contain exactly the same keys as the original translations: extra translations must not introduce keys that are absent from the original translations.
