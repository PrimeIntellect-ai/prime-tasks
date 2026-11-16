Support custom headers to be passed through
--cookies is supported, but there may be scenarios where the caller needs to pass other headers.
Therefore, a new `--requestHeaders` option (`-r` for short) is required.

### Additional contract requirements

- The `--requestHeaders` option (short form `-r`) accepts a JSON string of key/value pairs. Each pair is passed through as an HTTP header named `<key>` with value `<value>`.
- The outgoing request includes `Accept-Language: <value>` when `acceptLanguage` is supplied, and `pragma: no-cache` when `disableCache` is true. It also includes the custom headers from `requestHeaders` when supplied.
- When headers from multiple sources are present, their lines are ordered as `Accept-Language`, then `pragma: no-cache`, then the custom headers. When none of these values are supplied, no additional header lines are included.
