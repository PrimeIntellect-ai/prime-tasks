Add importOrderCaseInsensitive option again
There's value in sorting uppercase first: constants, constructors and functions become sorted in that order.

Support for case sensitive sorting was dropped here #63

### Additional contract requirements

- The public plugin option added by this change is named `importOrderCaseSensitive` (boolean, default `false`).
- When `importOrderCaseSensitive` is `true`, imports within each group and the import specifiers within each import statement are ordered using a case-sensitive natural sort that places uppercase letters before lowercase letters while still ordering numeric substrings numerically.
- When `importOrderCaseSensitive` is `false` or omitted, the existing case-insensitive natural sort is used.
- The option is exposed under the name `importOrderCaseSensitive`; this change does not add an `importOrderCaseInsensitive` option.
