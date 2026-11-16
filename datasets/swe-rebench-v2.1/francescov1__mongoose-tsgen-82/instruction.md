Poor Plural to Singular Renaming
In the current state, the plugin would rename "Classes" to "Classe" when converting from plural to singular. Clearly classe is not a proper word.

To fix this it's quite simple. [HIDDEN] This would properly rename words like "glasses", "passes", "classes", "masses", etc, while words like "vases", "houses" are still properly renamed, since they end in "ses", not "sses".

There are a few words that don't follow this rule: [https://www.thefreedictionary.com/words-that-end-in-sse](url) (I don't even know what any of these words mean)
However there are way too many that do: [https://www.thefreedictionary.com/words-that-end-in-ss](url)

### Additional contract requirements

- When a model has a subdocument array whose name ends in "sses" (for example `glasses` or `classes`), the generated subdocument type name must be singular with the trailing "es" removed: `StoreGlass` and `StoreClass` for a model named `Store`, not `StoreGlasse` or `StoreClasse`.
- When a subdocument array name ends in "ses" but not "sses" (for example `vases` or `houses`), the generated subdocument type name must still be singular with only the final "s" removed: `StoreVase` and `StoreHouse` for a model named `Store`.
