There should be an option to disable MAGIC_NUMBER rule in test sources

### Additional contract requirements

- The option is configured through the MAGIC_NUMBER rule configuration under the key `ignoreTest`.
- `ignoreTest` accepts the string values `"true"` and `"false"` (parsed as a boolean).
- When `ignoreTest` is `"true"`, the MAGIC_NUMBER rule does not report magic numbers in test sources.
- When `ignoreTest` is `"false"`, the MAGIC_NUMBER rule reports magic numbers in test sources as usual.
- The default value of `ignoreTest` is `"true"`: when the option is not supplied, magic numbers in test sources are not reported.
