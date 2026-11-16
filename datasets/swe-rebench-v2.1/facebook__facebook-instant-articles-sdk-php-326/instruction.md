Transformer does not give a warning for bad JSON
the Transformer->loadRules() adds no warning if the JSON is invalid.

https://github.com/facebook/facebook-instant-articles-sdk-php/blob/master/src/Facebook/InstantArticles/Transformer/Transformer.php#L384

### Additional contract requirements

- For syntactically malformed JSON, `loadRules()` must make `getLogs()[1]` an ERROR `TransformerLog` with the exact message `Invalid JSON Rules: Syntax error, malformed JSON`. For JSON with an unexpected control character, that entry must have the exact message `Invalid JSON Rules: Syntax error, malformed JSON` or `Invalid JSON Rules: Unexpected control character found`.
- When the JSON is invalid, `loadRules()` must also add a warning, so that `getWarnings()` is non-empty.
