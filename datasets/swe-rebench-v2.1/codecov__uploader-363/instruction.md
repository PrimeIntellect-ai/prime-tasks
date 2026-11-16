`generateQuery` does not encode query strings
Use the native [URLSearchParams](https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams) API as an abstraction for handling query strings. It both formats and encodes/decodes query strings.

The current tests for `generateQuery` appear to validate the return values against malformed URIs (e.g., slashes and whatnot are not encoded properly). In other words, any refactor to `generateQuery` will have to correct the tests.

### Additional contract requirements

- The query string is serialized with `application/x-www-form-urlencoded` semantics, as produced by the native `URLSearchParams` API. In particular, a space in a value is encoded as `+` (not `%20`).
- When `pr` is `0` or is not a valid number (for example `NaN`), it is serialized as an empty value, i.e. `pr=`.
