function for creating RegExp values
Similar to [`regex`][1] from PureScript's Data.String.Regex module.


[1]: https://github.com/purescript/purescript-strings/blob/v0.7.0/docs/Data/String/Regex.md#regex-1

### Additional contract requirements

Export `regex` on the Sanctuary namespace as a binary function taking the flags first and the source pattern second, and returning the corresponding JavaScript `RegExp`. It follows Sanctuary's currying convention, so supplying only the flags returns a function that accepts the source pattern. The flags argument identifies the regular-expression flags to use.
